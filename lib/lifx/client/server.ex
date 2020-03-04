defmodule Lifx.Client.Server do
  use GenServer
  use Lifx.Protocol.Types

  require Logger

  alias Lifx.Protocol.{FrameHeader, FrameAddress, ProtocolHeader}
  alias Lifx.Protocol.Packet
  alias Lifx.Protocol
  alias Lifx.Device

  @port 56700
  @multicast Application.get_env(:lifx, :multicast)
  @poll_discover_time Application.get_env(:lifx, :poll_discover_time)
  @udp Application.get_env(:lifx, :udp)

  defmodule State do
    @type t :: %__MODULE__{
            udp: port(),
            source: integer(),
            events: pid(),
            handlers: [{pid(), pid()}],
            devices: [Device.t()]
          }
    defstruct udp: nil,
              source: 0,
              events: nil,
              handlers: [],
              devices: []
  end

  @spec init(:ok) :: {:ok, State.t()}
  def init(:ok) do
    source = :rand.uniform(4_294_967_295)
    Logger.debug("LIFX Client: #{source}")

    # event handler
    import Supervisor.Spec
    child = worker(GenServer, [], restart: :temporary)

    {:ok, events} =
      Supervisor.start_link([child], strategy: :simple_one_for_one, name: Lifx.Client.Events)

    udp_options = [
      :binary,
      {:broadcast, true},
      {:ip, {0, 0, 0, 0}},
      {:reuseaddr, true}
    ]

    {:ok, udp} = @udp.open(0, udp_options)
    Process.send_after(self(), :discover, 0)

    {:ok, %State{source: source, events: events, udp: udp}}
  end

  def handle_cast({:update_device, device}, state) do
    state = update_device(device, state)
    {:noreply, state}
  end

  def handle_call(:discover, _from, state) do
    Logger.debug("Running discover on demand.")
    send_discovery_packet(state.source, state.udp)
    {:reply, :ok, state}
  end

  def handle_call({:handler, handler}, {pid, _}, state) do
    Supervisor.start_child(state.events, [handler, pid])
    {:reply, :ok, %{state | :handlers => [{handler, pid} | state.handlers]}}
  end

  def handle_call(:devices, _from, state) do
    {:reply, state.devices, state}
  end

  def handle_info(:discover, state) do
    Logger.debug("Running discover on timer.")
    send_discovery_packet(state.source, state.udp)
    Process.send_after(self(), :discover, @poll_discover_time)
    {:noreply, state}
  end

  def handle_info({:udp, _s, ip, _port, payload}, state) do
    state = process(ip, payload, state)
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    devices = Enum.reject(state.devices, fn device -> device.pid == pid end)
    {:noreply, %State{state | devices: devices}}
  end

  @spec lookup_device(atom(), State.t()) :: Device.t() | nil
  defp lookup_device(target, state) do
    device_list =
      state.devices
      |> Enum.filter(fn device -> device.id == target end)
      |> Enum.take(-1)

    case device_list do
      [device] -> device
      [] -> nil
    end
  end

  @spec warn_nil_device(Device.t(), String.t()) :: Device.t() | nil
  defp warn_nil_device(nil, msg) do
    Logger.info(msg)
    nil
  end

  defp warn_nil_device(%Device{} = device, _msg), do: device

  @spec update_device(Device.t() | nil, State.t()) :: State.t()

  defp update_device(nil, %State{} = state), do: state

  defp update_device(%Device{} = device, %State{} = state) do
    state =
      cond do
        Enum.any?(state.devices, fn dev -> dev.id == device.id end) ->
          %State{
            state
            | :devices =>
                Enum.map(state.devices, fn d ->
                  cond do
                    device.id == d.id -> device
                    true -> d
                  end
                end)
          }

        true ->
          %State{state | :devices => [device | state.devices]}
      end

    case Device.host_update(device) do
      :ok -> nil
      {:error, err} -> Logger.debug("Cannot contact new #{device.id}: #{err}.")
    end

    state
  end

  @spec dispatch_packet(Device.t() | nil, Packet.t(), State.t()) :: State.t()

  defp dispatch_packet(nil, _, %State{} = state), do: state

  defp dispatch_packet(%Device{} = device, %Packet{} = packet, %State{} = state) do
    case Device.packet(device, packet) do
      :ok -> nil
      {:error, err} -> Logger.debug("Cannot contact #{device.id}: #{err}.")
    end

    state
  end

  @spec handle_packet(Packet.t(), tuple(), State.t()) :: State.t()

  defp handle_packet(
         %Packet{:protocol_header => %ProtocolHeader{:type => @stateservice}} = packet,
         ip,
         state
       ) do
    target = packet.frame_address.target
    host = ip
    port = packet.payload.port

    device =
      case lookup_device(target, state) do
        nil ->
          device = %Device{
            id: target,
            pid: nil,
            host: host,
            port: port
          }

          result =
            Lifx.DeviceSupervisor.start_device(
              device,
              state.udp,
              state.source
            )

          case result do
            {:ok, child} ->
              _ref = Process.monitor(child)
              device = %Device{device | pid: child}
              Lifx.Poller.schedule_device(Lifx.Poller, device)
              device

            {:error, error} ->
              Logger.error("Cannot start device child process for #{target}: #{error}.")

              nil
          end

        device ->
          %Device{device | host: host, port: port}
      end

    update_device(device, state)
  end

  defp handle_packet(%Packet{:frame_address => %FrameAddress{:target => :all}}, _ip, state) do
    state
  end

  defp handle_packet(
         %Packet{:frame_address => %FrameAddress{:target => target}} = packet,
         _ip,
         state
       ) do
    target
    |> lookup_device(state)
    |> warn_nil_device("Cannot find device #{target}.")
    |> dispatch_packet(packet, state)
  end

  @spec process(tuple(), bitstring(), State.t()) :: State.t()
  defp process(ip, payload, state) do
    payload
    |> Protocol.parse_packet()
    |> handle_packet(ip, state)
  end

  @spec send_discovery_packet(integer(), port()) :: :ok | {:error, atom()}
  defp send_discovery_packet(source, udp) do
    @udp.send(
      udp,
      @multicast,
      @port,
      %Packet{
        :frame_header => %FrameHeader{:source => source, :tagged => 1},
        :frame_address => %FrameAddress{:res_required => 1},
        :protocol_header => %ProtocolHeader{:type => @getservice}
      }
      |> Protocol.create_packet()
    )
  end
end
