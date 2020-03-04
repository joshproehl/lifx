defmodule Lifx.Client do
  use Lifx.Protocol.Types

  require Logger

  alias Lifx.Device

  @spec start_link() :: {:ok, pid()}
  def start_link do
    GenServer.start_link(Lifx.Client.Server, :ok, name: __MODULE__)
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

  @spec update_device(Device.t()) :: :ok
  def update_device(%Device{} = device) do
    GenServer.cast(__MODULE__, {:update_device, device})
  end
end
