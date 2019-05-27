defmodule Lifx.Poller do
  use GenServer

  alias Lifx.Client
  alias Lifx.Device

  require Logger

  @poll_state_time Application.get_env(:lifx, :poll_state_time)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def schedule_device(pid, %Device{} = device) do
    Process.send_after(pid, {:poll_device, device}, 0)
  end

  def init(:ok) do
    reschedule()
    {:ok, %{}}
  end

  defp reschedule do
    if @poll_state_time != :disable do
      Process.send_after(self(), :poll_all, @poll_state_time)
    end
  end

  def handle_info(:poll_all, state) do
    Logger.debug("Polling all devices.")

    Enum.each(Client.devices(), fn device ->
      Process.send_after(self(), {:poll_device, device}, 0)
    end)

    reschedule()
    {:noreply, state}
  end

  def handle_info({:poll_device, device}, state) do
    Logger.debug("Polling device #{device.id}.")

    with {:ok, _} <- Device.get_location(device),
         {:ok, _} <- Device.get_label(device),
         {:ok, _} <- Device.get_group(device) do
      nil
    else
      _ -> nil
    end

    {:noreply, state}
  end
end
