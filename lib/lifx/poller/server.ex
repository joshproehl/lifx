defmodule Lifx.Poller.Server do
  @moduledoc false

  use GenServer

  alias Lifx.Client
  alias Lifx.Poller.Private

  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: Lifx.Poller)
  end

  def init(:ok) do
    Private.reschedule()
    {:ok, %{}}
  end

  def handle_info(:poll_all, state) do
    Private.poll_device_list(Client.devices())
    Private.reschedule()
    {:noreply, state}
  end

  def handle_info({:poll_device, device}, state) do
    Private.poll_device(device)
    {:noreply, state}
  end
end
