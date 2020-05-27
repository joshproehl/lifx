defmodule Lifx.EventSupervisor do
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

  def start_handler(handler, parent_pid) do
    spec = {handler, parent_pid}
    {:ok, _} = DynamicSupervisor.start_child(__MODULE__, spec)
    :ok
  end

  @spec notify(Device.t(), :updated | :deleted) :: :ok
  def notify(%Device{} = device, status) do
    for {_, pid, _, _} <- DynamicSupervisor.which_children(__MODULE__) do
      GenServer.cast(pid, {status, device})
    end

    :ok
  end
end
