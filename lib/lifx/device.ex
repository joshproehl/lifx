defmodule Lifx.Device do
  use GenServer, restart: :transient
  use Lifx.Protocol.Types
  require Logger
  alias Lifx.Protocol.{FrameHeader, FrameAddress, ProtocolHeader}
  alias Lifx.Protocol.Packet
  alias Lifx.Protocol.{HSBK, Group, Location}
  alias Lifx.Protocol
  alias Lifx.Client
  alias Lifx.Device

  @udp Application.get_env(:lifx, :udp)
  @max_api_timeout Application.get_env(:lifx, :max_api_timeout)
  @max_retries Application.get_env(:lifx, :max_retries)
  @wait_between_retry Application.get_env(:lifx, :wait_between_retry)

  @type t :: %__MODULE__{
          id: atom(),
          host: tuple(),
          port: integer(),
          label: String.t(),
          group: Group.t(),
          location: Location.t()
        }

  defstruct id: 0,
            host: {0, 0, 0, 0},
            port: 57600,
            label: nil,
            group: %Group{},
            location: %Location{}

  defmodule Pending do
    @type t :: %__MODULE__{
            packet: Packet.t(),
            payload: bitstring(),
            from: GenServer.server(),
            tries: integer(),
            timer: pid()
          }
    @enforce_keys [:packet, :payload, :from, :tries, :timer]
    defstruct packet: nil, payload: nil, from: nil, tries: 0, timer: nil
  end

  defmodule State do
    @type t :: %__MODULE__{
            id: atom(),
            host: tuple(),
            port: integer(),
            label: String.t(),
            group: Group.t(),
            location: Location.t(),
            udp: port(),
            source: integer(),
            sequence: integer(),
            pending_list: %{required(integer()) => Pending.t()}
          }

    defstruct id: nil,
              host: {0, 0, 0, 0},
              port: 57600,
              label: nil,
              group: %Group{},
              location: %Location{},
              udp: nil,
              source: 0,
              sequence: 0,
              pending_list: %{}
  end

  @spec prefix(State.t()) :: String.t()
  defp prefix(state) do
    "Device #{state.id}/#{state.label}:"
  end

  @spec state_to_device(State.t()) :: Device.t()
  def state_to_device(%State{} = state) do
    %Device{
      id: state.id,
      host: state.host,
      port: state.port,
      label: state.label,
      group: state.group,
      location: state.location
    }
  end

  @spec start_link(Device.t(), port(), integer()) :: {:ok, pid()}
  def start_link(%Device{} = device, udp, source) do
    state = %State{
      id: device.id,
      host: device.host,
      port: device.port,
      label: device.label,
      group: device.group,
      location: device.location,
      udp: udp,
      source: source
    }

    GenServer.start_link(__MODULE__, state, name: state.id)
  end

  @spec send_and_forget(atom(), integer(), bitstring()) :: :ok
  defp send_and_forget(id, protocol_type, payload) do
    GenServer.cast(id, {:send, protocol_type, payload})
    :ok
  end

  @spec send_and_wait(atom(), integer(), bitstring()) :: {:ok, bitstring()} | {:error, String.t()}
  defp send_and_wait(id, protocol_type, payload) do
    request = {:send, protocol_type, payload}

    with {:ok, payload} <- GenServer.call(id, request, @max_api_timeout) do
      {:ok, payload}
    else
      {:error, err} -> {:error, err}
    end
  catch
    :exit, {:noproc, _} -> {:error, "The device #{id} is dead"}
  end

  @spec set_color(Device.t(), HSBK.t(), integer) :: :ok
  def set_color(%Device{id: id}, %HSBK{} = hsbk, duration \\ 1000) do
    payload = Protocol.hsbk(hsbk, duration)
    send_and_forget(id, @light_setcolor, payload)
  end

  @spec on(Device.t()) :: :ok
  def on(%Device{} = device) do
    set_power(device, 65535)
  end

  @spec off(Device.t()) :: :ok
  def off(%Device{} = device) do
    set_power(device, 0)
  end

  @spec set_power(Device.t(), integer) :: :ok
  def set_power(%Device{id: id}, power) do
    payload = Protocol.level(power)
    send_and_forget(id, @setpower, payload)
  end

  @spec set_color_wait(Device.t(), HSBK.t(), integer) :: {:ok, HSBK.t()} | {:error, String.t()}
  def set_color_wait(%Device{id: id}, %HSBK{} = hsbk, duration \\ 1000) do
    payload = Protocol.hsbk(hsbk, duration)

    case send_and_wait(id, @light_setcolor, payload) do
      {:ok, value} -> {:ok, value.hsbk}
      {:error, value} -> {:error, value}
    end
  end

  @spec on_wait(Device.t()) :: {:ok, HSBK.t()} | {:error, String.t()}
  def on_wait(%Device{} = device) do
    set_power_wait(device, 65535)
  end

  @spec off_wait(Device.t()) :: {:ok, HSBK.t()} | {:error, String.t()}
  def off_wait(%Device{} = device) do
    set_power_wait(device, 0)
  end

  @spec set_power_wait(Device.t(), integer) :: {:ok, HSBK.t()} | {:error, String.t()}
  def set_power_wait(%Device{id: id}, power) do
    payload = Protocol.level(power)

    case send_and_wait(id, @setpower, payload) do
      {:ok, value} -> {:ok, value.level}
      {:error, value} -> {:error, value}
    end
  end

  @spec get_location(Device.t()) :: {:ok, Location.t()} | {:error, String.t()}
  def get_location(%Device{id: id}) do
    payload = <<>>

    case send_and_wait(id, @getlocation, payload) do
      {:ok, value} -> {:ok, value.location}
      {:error, value} -> {:error, value}
    end
  end

  @spec get_label(Device.t()) :: {:ok, String.t()} | {:error, String.t()}
  def get_label(%Device{id: id}) do
    payload = <<>>

    case send_and_wait(id, @getlabel, payload) do
      {:ok, value} -> {:ok, value.label}
      {:error, value} -> {:error, value}
    end
  end

  @spec get_color(Device.t()) :: {:ok, HSBK.t()} | {:error, String.t()}
  def get_color(%Device{id: id}) do
    payload = <<>>

    case send_and_wait(id, @light_get, payload) do
      {:ok, value} -> {:ok, value.hsbk}
      {:error, value} -> {:error, value}
    end
  end

  @spec get_wifi(Device.t()) :: {:ok, Packet.t()} | {:error, String.t()}
  def get_wifi(%Device{id: id}) do
    payload = <<>>

    case send_and_wait(id, @getwifiinfo, payload) do
      {:ok, value} -> {:ok, value}
      {:error, value} -> {:error, value}
    end
  end

  @spec get_power(Device.t()) :: {:ok, integer} | {:error, String.t()}
  def get_power(%Device{id: id}) do
    payload = <<>>

    case send_and_wait(id, @getpower, payload) do
      {:ok, value} -> {:ok, value.level}
      {:error, value} -> {:error, value}
    end
  end

  @spec get_group(Device.t()) :: {:ok, Group.t()} | {:error, String.t()}
  def get_group(%Device{id: id}) do
    payload = <<>>

    case send_and_wait(id, @getgroup, payload) do
      {:ok, value} -> {:ok, value.group}
      {:error, value} -> {:error, value}
    end
  end

  @spec packet(atom(), Packet.t()) :: Device.t()
  def packet(id, %Packet{} = packet) do
    GenServer.call(id, {:packet, packet}) |> state_to_device()
  end

  @spec host_update(GenServer.server(), tuple(), integer) :: Device.t()
  def host_update(id, host, port) do
    GenServer.call(id, {:update_host, host, port}) |> state_to_device()
  end

  @spec init(State.t()) :: {:ok, State.t()}
  def init(%State{} = device) do
    Lifx.Poller.schedule_device(Lifx.Poller, device |> state_to_device())
    {:ok, device}
  end

  @spec handle_packet(Packet.t(), State.t()) :: State.t()
  defp handle_packet(
         %Packet{:protocol_header => %ProtocolHeader{:type => @statelabel}} = packet,
         state
       ) do
    %State{state | :label => packet.payload.label} |> notify(:updated)
  end

  defp handle_packet(
         %Packet{:protocol_header => %ProtocolHeader{:type => @stategroup}} = packet,
         state
       ) do
    %State{state | :group => packet.payload.group} |> notify(:updated)
  end

  defp handle_packet(
         %Packet{:protocol_header => %ProtocolHeader{:type => @statelocation}} = packet,
         state
       ) do
    %State{state | :location => packet.payload.location} |> notify(:updated)
  end

  defp handle_packet(_packet, state) do
    state
  end

  def handle_call({:packet, %Packet{} = packet}, _from, state) do
    state = handle_packet(packet, state)
    sequence = packet.frame_address.sequence

    state =
      if Map.has_key?(state.pending_list, sequence) do
        pending = state.pending_list[sequence]
        Process.cancel_timer(pending.timer)

        if not is_nil(pending.from) do
          Logger.debug("#{prefix(state)} Got seq #{sequence}, alerting sender.")
          GenServer.reply(pending.from, {:ok, packet.payload})
        else
          Logger.debug("#{prefix(state)} Got seq #{sequence}, not alerting sender.")
        end

        Map.update(state, :pending_list, nil, &Map.delete(&1, sequence))
      else
        Logger.debug("#{prefix(state)} Got seq #{sequence}, no record, presumed already done.")
        state
      end

    {:reply, state, state}
  end

  def handle_call({:update_host, host, port}, _from, state) do
    s = %State{state | :host => host, :port => port} |> notify(:updated)
    {:reply, s, s}
  end

  def handle_call({:send, protocol_type, payload}, from, state) do
    packet = %Packet{
      :frame_header => %FrameHeader{},
      :frame_address => %FrameAddress{target: state.id, res_required: 1},
      :protocol_header => %ProtocolHeader{type: protocol_type}
    }

    state = schedule_packet(state, packet, payload, from)
    {:noreply, state}
  end

  def handle_cast({:send, protocol_type, payload}, state) do
    packet = %Packet{
      :frame_header => %FrameHeader{},
      :frame_address => %FrameAddress{target: state.id, res_required: 1},
      :protocol_header => %ProtocolHeader{type: protocol_type}
    }

    state = schedule_packet(state, packet, payload, nil)
    {:noreply, state}
  end

  @spec schedule_packet(State.t(), Packet.t(), bitstring(), GenServer.server()) :: State.t()
  defp schedule_packet(state, packet, payload, from) do
    sequence = state.sequence
    Logger.debug("#{prefix(state)} Scheduling seq #{sequence}.")

    packet = put_in(packet.frame_address.sequence, sequence)

    timer = Process.send_after(self(), {:send, sequence}, 0)

    pending = %Pending{
      packet: packet,
      payload: payload,
      from: from,
      tries: 0,
      timer: timer
    }

    next_sequence = rem(sequence + 1, 256)

    state
    |> Map.put(:sequence, next_sequence)
    |> Map.update(:pending_list, nil, &Map.put(&1, sequence, pending))
  end

  @spec handle_info({:send, integer}, State.t()) ::
          {:noreply, State.t()} | {:stop, :normal, State.t()}
  def handle_info({:send, sequence}, state) do
    if Map.has_key?(state.pending_list, sequence) do
      pending = state.pending_list[sequence]

      cond do
        pending.tries < @max_retries ->
          Logger.debug("#{prefix(state)} Sending seq #{sequence} tries #{pending.tries}.")
          send(state, pending.packet, pending.payload)
          timer = Process.send_after(self(), {:send, sequence}, @wait_between_retry)
          pending = %Pending{pending | tries: pending.tries + 1, timer: timer}
          state = Map.update(state, :pending_list, nil, &Map.put(&1, sequence, pending))
          {:noreply, state}

        true ->
          Logger.debug(
            "#{prefix(state)} Failed sending seq #{sequence} tries #{pending.tries}, killing light."
          )

          Client.remove_device(state |> state_to_device())
          notify(state, :deleted)

          Enum.each(state.pending_list, fn {_, p} ->
            GenServer.reply(p.from, {:error, "Too many retries"})
          end)

          state = Map.update(state, :pending_list, nil, &Map.delete(&1, sequence))
          {:stop, :normal, state}
      end
    else
      Logger.debug("#{prefix(state)} Sending seq #{sequence}, no record, presumed already done.")
      {:noreply, state}
    end
  end

  @spec send(State.t(), Packet.t(), bitstring()) :: :ok
  defp send(%State{} = state, %Packet{} = packet, payload) do
    @udp.send(
      state.udp,
      state.host,
      state.port,
      %Packet{
        packet
        | :frame_header => %FrameHeader{packet.frame_header | :source => state.source}
      }
      |> Protocol.create_packet(payload)
    )

    :ok
  end

  @spec notify(State.t(), :updated | :deleted) :: :ok
  defp notify(state, status) do
    device = state_to_device(state)

    for {_, pid, _, _} <- Supervisor.which_children(Lifx.Client.Events) do
      GenServer.cast(pid, {status, device})
    end

    state
  end
end
