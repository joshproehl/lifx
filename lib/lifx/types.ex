defmodule Lifx.Protocol.Types do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
      @getservice 2
      @stateservice 3
      @gethostinfo 12
      @statehostinfo 13
      @gethostfirmware 14
      @statehostfirmware 15
      @getwifiinfo 16
      @statewifiinfo 17
      @getwififirmware 18
      @statewififirmware 19
      @getpower 20
      @setpower 21
      @statepower 22
      @getlabel 23
      @setlabel 24
      @statelabel 25
      @getversion 32
      @stateversion 33
      @getinfo 34
      @stateinfo 35
      @acknowledgement 45
      @getlocation 48
      @statelocation 50
      @getgroup 51
      @stategroup 53
      @echorequest 58
      @echoresponse 59
      @light_get 101
      @light_setcolor 102
      @light_state 107
      @light_getpower 116
      @light_setpower 117
      @light_statepower 118
      @set_extended_color_zones 510
      @get_extended_color_zones 511
      @state_extended_color_zones 512
    end
  end
end
