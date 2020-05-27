defmodule Lifx.Client do
  @moduledoc false

  use Lifx.Protocol.Types

  require Logger

  alias Lifx.Device

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
end
