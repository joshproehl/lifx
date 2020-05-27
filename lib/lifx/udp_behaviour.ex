defmodule Lifx.UdpBehaviour do
  @moduledoc false
  @callback open(integer(), list()) :: {:ok, port()} | {:error, any()}
  @callback send(port(), {byte(), byte(), byte(), byte()}, integer(), bitstring()) ::
              :ok | {:error, any()}
end
