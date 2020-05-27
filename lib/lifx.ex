defmodule Lifx do
  @moduledoc false

  use Application
  require Logger

  def start(_type, _args) do
    {:ok, _pid} = Lifx.Supervisor.start_link()
  end
end
