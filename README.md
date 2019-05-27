# Lifx

**A Client for Lifx LAN API**

Automatically discover and control all of your [Lifx](http://lifx.com) lightbulbs.

## Use

    1. git clone https://github.com/brianmay/lifx.git
    2. mix do deps.get, deps.compile
    3. iex -S mix

## Explanation

As long as you are on the same subnet as your lightbulbs, you should see some information in stdout about devices being discovered

    Starting Device
    %Lifx.Device{
        group: %Lifx.Protocol.Group{
            id: [],
            label: nil,
            updated_at: 0
        },
        host: {192, 168, 1, 118},
        id: :"193196534887376",
        label: nil,
        location: %Lifx.Protocol.Location{
            id: [],
            label: nil,
            updated_at: 0
        },
        port: 56700,
    }

What's shown here is the initial state of the bulb. Shortly after the bulb is discovered it will gather the state information, and update it every 5 seconds.

## Architecture

![Architecture Image](./images/lifx_architecture.png)

`Lifx.Client` is a small UDP server running on a randomly selected available port. As a new device is discovered a process is spawned and added to the device list maintained by `Lifx.Client`.

Every 5 seconds the device process queries itself for updated information. Only basic information is kept, such as connection information, group, and location. The updated information is then broadcast (using notify) over `Lifx.Client.Events` event bus. Anyone can add a handler to the event bus to handle updated device state by calling `Lifx.Client.add_handler`. See `Lifx.Handler` for an example implementation of an event handler.

If the device cannot be contacted, it is considered dead. A deleted notification is broadcast, and the device removed from the device list.

There's a good chance that by the time you've added your handler to `Lifx.Client` that device discovery has already happened. Luckily `Lifx.Client` also keeps a list of the known devices. You can return the currently known devices by calling `Lifx.Client.devices` which returns something similar to this.

    [
        %Lifx.Device{
            group: %Lifx.Protocol.Group{
                id: <<251, 202, 127, 40, 82, 243, 115, 230, 221, 64, 134, 187, 206, 118, 102, 156>>,
                label: "Lab",
                updated_at: 13888846944200582420
            },
            host: {192, 168, 1, 118},
            id: :"193196534887376",
            label: "Bulb 2",
            location: %Lifx.Protocol.Location{
                id: <<205, 66, 137, 157, 220, 168, 133, 96, 147, 254, 0, 111, 52, 160, 229, 6>>,
                label: "CRT Lab",
                updated_at: 13836094609682883860
            },
            port: 56700,
        },
        %Lifx.Device{
            group: %Lifx.Protocol.Group{
                id: <<251, 202, 127, 40, 82, 243, 115, 230, 221, 64, 134, 187, 206, 118, 102, 156>>,
                label: "Lab",
                updated_at: 13868661424052266260
            },
            host: {192, 168, 1, 60},
            id: :"204217420968912",
            label: "Bulb 1",
            location: %Lifx.Protocol.Location{
                id: <<205, 66, 137, 157, 220, 168, 133, 96, 147, 254, 0, 111, 52, 160, 229, 6>>,
                label: "CRT Lab",
                updated_at: 9281461546755319060
            },
            port: 56700,
        }
    ]

`Lifx.Protocol` handles all protocol related functions, parsing and creating packets as well as payloads.

In order to communicate with a single bulb, in a network that may contain multiple devices you would use the `Lifx.Device` interface `Lifx.Device.set_color(device, %Lifx.Protocol.HSBK{}, duration)` where device is `Lifx.Device`
