defmodule Lifx.Poller do
  alias Lifx.Device

  require Logger

  def start_link(_opts) do
    GenServer.start_link(Lifx.Poller.Server, :ok, name: __MODULE__)
  end

  def schedule_device(pid, %Device{} = device) do
    Process.send_after(pid, {:poll_device, device}, 0)
  end
end
