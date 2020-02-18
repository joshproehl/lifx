defmodule Lifx.Device.Server do
  use GenServer, restart: :transient
  use Lifx.Protocol.Types
  require Logger
  alias Lifx.Protocol.{FrameHeader, FrameAddress, ProtocolHeader}
  alias Lifx.Protocol.Packet
  alias Lifx.Protocol.{Group, Location}
  alias Lifx.Protocol
  alias Lifx.Client
  alias Lifx.Device

  @udp Application.get_env(:lifx, :udp)
  @max_retries Application.get_env(:lifx, :max_retries)
  @wait_between_retry Application.get_env(:lifx, :wait_between_retry)

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
  defp state_to_device(%State{} = state) do
    %Device{
      id: state.id,
      host: state.host,
      port: state.port,
      label: state.label,
      group: state.group,
      location: state.location
    }
  end

  @spec init({Device.t(), port(), integer()}) :: {:ok, State.t()}
  def init({device, udp, source}) do
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

    Lifx.Poller.schedule_device(Lifx.Poller, device)
    {:ok, state}
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

    {:reply, state |> state_to_device(), state}
  end

  def handle_call({:update_host, host, port}, _from, state) do
    s = %State{state | :host => host, :port => port} |> notify(:updated)
    {:reply, s |> state_to_device(), s}
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
            if not is_nil(pending.from) do
              Logger.debug("#{prefix(state)} Too many retries, alerting sender.")
              GenServer.reply(p.from, {:error, "Too many retries"})
            else
              Logger.debug("#{prefix(state)} Too many retries, not alerting sender.")
            end
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
