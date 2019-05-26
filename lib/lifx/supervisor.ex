defmodule Lifx.Supervisor do
  use Supervisor
  require Logger

  def start_link do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    children = [
      worker(Lifx.Client, []),
      worker(Lifx.Poller, [[name: Lifx.Poller]]),
      supervisor(Task.Supervisor, [[name: Lifx.Client.PacketSupervisor]]),
      supervisor(Lifx.DeviceSupervisor, [])
    ]

    supervise(children, strategy: :one_for_one)
  end
end
