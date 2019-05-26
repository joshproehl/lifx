defmodule Lifx.Udp do
    @behaviour Lifx.UdpBehaviour

    def open(port, options) do
        :gen_udp.open(port, options)
    end


    def send(socket, host, port, payload) do
        :gen_udp.send(socket, host, port, payload)
    end
end

