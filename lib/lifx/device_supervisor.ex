defmodule Lifx.DeviceSupervisor do
  @moduledoc false

  use DynamicSupervisor
  use Lifx.Protocol.Types
  require Logger
  alias Lifx.Device

  def start_link do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_device(%Device{} = device, udp, source) do
    Logger.debug("Starting Device #{inspect(device)}")
    spec = {Lifx.Device.Server, {device, udp, source}}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end
end
