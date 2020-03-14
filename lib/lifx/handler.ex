defmodule Lifx.Handler do
  use GenServer
  require Logger
  alias Lifx.Device

  def init(parent_pid) do
    {:ok, parent_pid}
  end

  def start_link(parent_pid) do
    GenServer.start_link(__MODULE__, parent_pid)
  end

  def handle_cast({_, %Device{}} = msg, parent_pid) do
    send(parent_pid, msg)
    {:noreply, parent_pid}
  end
end
