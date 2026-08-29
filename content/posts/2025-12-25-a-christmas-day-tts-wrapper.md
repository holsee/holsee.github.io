---
title: "chatterbex: a Python TTS model behind an Erlang Port"
description: "Zero-shot voice cloning from Elixir over a plain Port to a Python subprocess: why not a NIF, why not HTTP, and the line-mode trap that meant the first commit could never have worked."
tags: [personal, elixir, oss]
draft: true
---

I wrapped a text-to-speech model in Elixir today. It's Christmas, the house is quiet, and Resemble AI's Chatterbox does zero-shot voice cloning that I wanted to call from the BEAM, and no wrapper existed. So: [chatterbex](https://github.com/holsee/chatterbex), eight commits, all dated the 25th of December. It's a small thing and a nice illustration of the least glamorous way to bind Elixir to a Python model, and of how the first commit shipped a bug that made it impossible for it to have worked at all.

## The boundary: a Port, not a NIF

The interesting decision in any "call Python from Elixir" library is where the boundary goes, and I wrote an ADR to argue myself out of the tempting options. Not a NIF: a long-running ML inference call would block a scheduler for seconds, which is the whole sin. Not erlport or Pythonx: extra dependencies for something the standard library already does. Not an HTTP server: a whole network surface for a local model. Not Nx or Bumblebee: Chatterbox isn't available in any format they load.

What's left is the oldest tool in the box, an Erlang Port to a Python subprocess, talking JSON over stdin and stdout:

```elixir
# lib/chatterbex/server.ex
port =
  Port.open({:spawn_executable, System.find_executable("python3")}, [
    :binary,
    :exit_status,
    {:args, [python_script]},
    {:env, [{~c"PYTHONUNBUFFERED", ~c"1"}]},
    {:line, 1_000_000}
  ])
```

The Python side is a 200-line script that loads the model once and then loops on stdin:

```python
def main():
    bridge = ChatterboxBridge()
    for line in sys.stdin:
        request = json.loads(line)
        if request["type"] == "init":
            response = bridge.init_model(...)
        elif request["type"] == "generate":
            response = bridge.generate(...)
        print(json.dumps(response), flush=True)
```

Audio comes back as base64 in a JSON line; the Elixir side decodes it to a WAV binary, and `Chatterbex.save/2` is a one-line `File.write`. A GenServer owns one port, one loaded model, one in-flight request. `start_link` blocks in `init` for up to five minutes because the first launch downloads a gigabyte or two of weights, and returning early would hand you a server that isn't ready. That's the whole design.

## The bug in commit one

Here's the part worth writing down. The very first commit opened the port in **line mode** (`{:line, 1_000_000}`) but its receive clause matched the raw form:

```elixir
handle_info({port, {:data, data}}, state)
```

A port in line mode never sends `{:data, data}`. It sends `{:data, {:eol, line}}` for a complete line and `{:data, {:noeol, chunk}}` for a fragment. So the pattern above matches nothing the port ever emits. The first commit's server could send a request and would then sit forever, because it could not recognise a single reply. It could not have worked.

The second commit, ninety minutes later, is titled "Fix Server port handling to use line-based parsing", and it adds the two clauses that were missing plus a buffer for the `:noeol` fragments, because a base64 WAV is comfortably larger than any line limit and arrives in pieces. I mention it not to flagellate myself over a Christmas Day typo, but because it's the standard shape of the Port-mode trap: you choose line mode for the sender and forget that line mode also changes what the receiver is handed. The framing you pick on one side of a boundary silently changes the messages on the other.

## What eight commits bought

Between the first commit and the last, seven hours apart: the line-buffering fix, Apple Silicon support (a `torch.load` monkey-patch to remap CUDA tensors onto MPS, with a per-component fallback to CPU when MPS refuses), three example scripts, and the Python-version gate that pins it to 3.10 or 3.11 because the model's numpy dependency doesn't build on 3.12 yet. Four tests, all of pure functions (the sample rate, the language list, the tag list, the file write), and nothing that exercises the port, because standing up a gigabyte model in CI on Christmas Day was not the assignment.

It went to hex the same week. It's alpha, it's one afternoon's work, and it does exactly one thing: it lets me say a sentence in Elixir and hear it back in a cloned voice. Some libraries don't need to be more than that.

## Where to look

- Repo: https://github.com/holsee/chatterbex; hex package `chatterbex`.
