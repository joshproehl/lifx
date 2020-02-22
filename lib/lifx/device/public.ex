defmodule Lifx.Device do
  use Lifx.Protocol.Types
  require Logger
  alias Lifx.Protocol.Packet
  alias Lifx.Protocol.{HSBK, Group, Location}
  alias Lifx.Protocol
  alias Lifx.Device

  @max_api_timeout Application.get_env(:lifx, :max_api_timeout)

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

  @spec start_link(Device.t(), port(), integer()) :: {:ok, pid()}
  def start_link(%Device{} = device, udp, source) do
    GenServer.start_link(Lifx.Device.Server, {device, udp, source}, name: device.id)
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

  @spec get_wifi(Device.t()) :: {:ok, map()} | {:error, String.t()}
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
    GenServer.call(id, {:packet, packet})
  end

  @spec host_update(GenServer.server(), tuple(), integer) :: Device.t()
  def host_update(id, host, port) do
    GenServer.call(id, {:update_host, host, port})
  end
end
