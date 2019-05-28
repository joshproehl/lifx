defmodule Lifx.Client do
  use GenServer
  use Lifx.Protocol.Types

  require Logger

  alias Lifx.Protocol.{FrameHeader, FrameAddress, ProtocolHeader}
  alias Lifx.Protocol.Packet
  alias Lifx.Protocol
  alias Lifx.Device
  alias Lifx.Client.PacketSupervisor

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

  @spec start_link() :: {:ok, pid()}
  def start_link do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @spec discover() :: :ok
  def discover do
    GenServer.call(__MODULE__, :discover)
  end

  @spec devices() :: [Device.t()]
  def devices do
    GenServer.call(__MODULE__, :devices)
  end

  @spec add_handler(pid()) :: :ok
  def add_handler(handler) do
    GenServer.call(__MODULE__, {:handler, handler})
  end

  @spec remove_device(Device.t()) :: :ok
  def remove_device(%Device{} = device) do
    GenServer.call(__MODULE__, {:remove_device, device})
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

  def handle_call({:remove_device, device}, _from, state) do
    devices = Enum.filter(state.devices, fn dev -> dev.id != device.id end)
    state = %State{state | devices: devices}
    {:reply, :ok, state}
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
    Task.Supervisor.start_child(PacketSupervisor, fn -> process(ip, payload, state) end)
    {:noreply, state}
  end

  def handle_info(%Device{} = device, state) do
    new_state =
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

    {:noreply, new_state}
  end

  @spec handle_packet(Packet.t(), tuple(), State.t()) :: :ok

  defp handle_packet(
         %Packet{:protocol_header => %ProtocolHeader{:type => @stateservice}} = packet,
         ip,
         state
       ) do
    target = packet.frame_address.target
    host = ip
    port = packet.payload.port

    case Process.whereis(target) do
      nil ->
        Lifx.DeviceSupervisor.start_device(
          %Device{
            :id => target,
            :host => host,
            :port => port
          },
          state.udp,
          state.source
        )

      _ ->
        true
    end

    updated = Device.host_update(target, host, port)
    Process.send(__MODULE__, updated, [])
  end

  defp handle_packet(%Packet{:frame_address => %FrameAddress{:target => :all}}, _ip, _state) do
    :ok
  end

  defp handle_packet(
         %Packet{:frame_address => %FrameAddress{:target => target}} = packet,
         _ip,
         _state
       ) do
    d = Device.packet(target, packet)
    Process.send(__MODULE__, d, [])
  end

  @spec process(tuple(), bitstring(), State.t()) :: :ok
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
