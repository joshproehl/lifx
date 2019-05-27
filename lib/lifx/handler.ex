defmodule Lifx.Handler do
  use GenServer
  require Logger
  alias Lifx.Device

  def init(args) do
    {:ok, args}
  end

  def handle_cast({_, %Device{}} = msg, parent) do
    send(parent, msg)
    {:noreply, parent}
  end
end
