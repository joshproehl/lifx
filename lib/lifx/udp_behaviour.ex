defmodule Lifx.UdpBehaviour do
  @callback open(integer(), keyword()) :: {:ok, port()} | {:error, any()}
  @callback send(port(), String.t(), integer(), bitstring()) :: :ok | {:error, any()}
end
