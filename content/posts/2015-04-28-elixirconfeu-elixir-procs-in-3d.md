---
title: "ElixirConfEU - Elixir Processes in 3D"
description: "A lightning talk at ElixirConfEU on visualizing Elixir processes in 3D."
tags:
  - elixir
---
I gave a lightning talk at [ElixirConfEU](http://ElixirConf.eu) on Visualizing Elixir Processes in 3D.

![Giving the lightning talk at ElixirConfEU](/images/exconfeu/elixirconf_lightning_talk.jpg)

::video{youtube="UdJL3MNsyMc" title="Steven Holdsworth, Elixir Processes in 3D, ElixirConf.EU 2015"}

A few nights before travelling to Krakow I had watched a video by [Kresten Krab Thorup](https://github.com/krestenkrab/) on his project [Erlubi](https://github.com/krestenkrab/erlubi) which transmits basic details of the Erlang VM to a [Ubigraph Server](http://ubietylab.net).

I started to use this to inspect Erlang projects, and play about with OTP Supervisor trees and how they looked in 3D.

I decided to go about using this from elixir. It doesn't take much to use from elixir; if you want to visualize your own project simply cherry pick the steps 1, 3, 6 and 7 below.

**1** Download the Ubigraph server from [ubietylab.net](http://ubietylab.net). Unpack it and just run the command line tool `bin/ubigraph_server`. A black window will appear.

**2** Create a new elixir project `mix new lightning_ex` and cd into directory.

**3** Add Erlubi as a dependency to the mix.exs file:

```elixir
defp deps do
  [{:erlubi, github: "krestenkrab/erlubi"}]
end
```

**4** Add some code to ex_lightning.ex to generate linked and unlinking procs

```elixir
defmodule ExLightning do
  def start_linked(n) do
    for _ <- 1..n do
      Task.start_link(fn ->
        :timer.sleep(1000)
      end)
    end
  end

  def start(n) do
    for _ <- 1..n do
      Task.start(fn ->
        :timer.sleep(1000)
      end)
    end
  end
end
```

**5** In terminal fetch dependencies and compile with `mix do deps.get, compile`

**6** In terminal start an iex session with mix `iex -S mix`

**7** In iex session start Erlubi tracer with `:erlubi_tracer.run`. If you get an error ensure you started ubigraph_server as described in step 1. At this point you should see the vanilla elixir system visualized in 3D like so:

- Green Cubes = Erlang Ports
- Red Spheres = Erlang Processes
- Blue Sphere = Named Erlang Processes
- Grey Line = Process Links

![Erlubi 3D visualization: a vanilla process tree](/images/exconfeu/erlubi_vanilla.png)

**8** run `ExLightning.start 5000` which will create 5000 unlinked processes (unbound red spheres)

![Erlubi 3D visualization: processes without links](/images/exconfeu/erlubi_unlinked.png)

**9** run `ExLightning.start_linked 5000` which will create 5000 linked processes, which will be linked to the creating process.

![Erlubi 3D visualization: processes with links shown](/images/exconfeu/erlubi_linked.png)

Full source code can be found here: [github.com/holsee/lightning_ex](https://github.com/holsee/lightning_ex)

Have fun :D
