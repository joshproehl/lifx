defmodule Lifx.Udp do
  @moduledoc false
  @behaviour Lifx.UdpBehaviour

  @spec open(integer(), list()) :: {:ok, port()} | {:error, any()}
  def open(port, options) do
    :gen_udp.open(port, options)
  end

  @spec send(port(), {byte(), byte(), byte(), byte()}, integer(), bitstring()) ::
          :ok | {:error, any()}
  def send(socket, host, port, payload) do
    :gen_udp.send(socket, host, port, payload)
  end
end
