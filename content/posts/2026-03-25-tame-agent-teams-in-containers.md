---
title: "tame: one container per coding agent"
description: "Four Claude Code sessions on one laptop and no idea what any of them was doing. So: a container per agent, a tmux window each, status as files rather than a protocol, the network decided from outside, and the token fetched from the Keychain so nothing is baked into an image."
tags: [personal, agents, asdlc, docker, security]
---

Last weekend I had four coding-agent sessions running on one laptop, each holding its own context, and I couldn't have told you what any of them was doing without clicking into it. That's not a workflow, that's a browser with too many tabs. So I wrote a harness. It's Go, it's called `tame` (Terminal Agent Management Environment), and it's already at v0.1.2.

## what it is

Each agent session runs in its own Docker container from a pre-baked image, gets its own tmux window, and keeps a record of what it's doing outside the session so I can look without interrupting:

```bash
cd ~/my-project
tame run "Fix the failing test in auth_test.go"
tame status fix-the-failing-test-3a7f
tame attach fix-the-failing-test-3a7f
```

`run` mounts the current directory, inherits the API key, starts Claude Code with the task and generates a session name. Sessions group under a `--project`, list with `tame ls`, stream logs with `tame logs`, and there's a small web dashboard for the same view. `--autonomous --max-iterations 10` runs the loop unattended until it's done or it hits the cap.

## status is a file, not a protocol

The bit I'm happiest with is how the harness knows what an agent is doing. Inside the container there's a `tame-report` CLI:

```bash
tame-report update --topic "Fix bug" --status working --current "Reading logs"
tame-report update --completed "Found root cause" --current "Writing fix"
tame-report done --summary "Bug fixed, test added"
```

It writes `status.json` (the current snapshot) and `timeline.jsonl` (the full history) into a bind-mounted directory, and the harness reads the files. No socket, no RPC, no agent-side networking to secure. `tame status --timeline` is `cat` with manners.

The agent learns all of this from a `TAME.md` injected into the container: session identity, the task and any detailed instructions, the workspace layout and mount permissions, the reporting reference. For Claude Code specifically it also gets a `CLAUDE.md`, a `tame-report` skill file, and a `.claude.json` pre-seeded to skip the onboarding wizard, because nothing stalls an unattended run like a theme picker.

## the network is decided from outside

Containers make the network a thing you set from outside the agent, and for agents that's most of the security model. A coding agent with a shell can `npm install` anything, `npm install` runs post-install scripts, and post-install scripts fetch things. I run agents against Elixir codebases. They do not need npm, or unpkg, or jsDelivr, or esm.sh, but an agent that decides it wants a JavaScript tool will go and get one, because that's what the training data does, and every one of those fetches is a supply-chain door I didn't open on purpose.

You can tell the model not to. You can write it in the system prompt in capitals. I'd rather the `curl` simply fail. So alongside the container's own network settings there's a hundred lines of bash for the host: macOS ships PF, the BSD packet filter, and the script resolves each registry and CDN hostname and writes a `block drop out` rule per address:

```bash
for domain in $(get_domains "$provider"); do
  for ip in $(dig +short A "$domain"); do
    echo "block drop out inet to ${ip}   # ${domain}" >> "$OUTPUT"
  done
  for ip6 in $(dig +short AAAA "$domain"); do
    echo "block drop out inet6 to ${ip6} # ${domain}" >> "$OUTPUT"
  done
done
```

The output is an anchor file that `/etc/pf.conf` loads; `pfctl -vnf` dry-runs it and `pfctl -d` turns it off when you actually want npm back. It's blunt and leaky: it blocks addresses rather than names, CDN addresses move, it blocks *you* on that machine too, and it's macOS-only. I'm fine with all of that. A denylist at the OS is one file, it doesn't care which harness or model is running, and it doesn't degrade when the model gets confident. The clever bit of an agent setup should be the model. Everything around it should be boring and hard to argue with.

## zero-touch auth

The commits that made it feel finished were about credentials. On macOS, Claude Code's OAuth token lives in the Keychain. `tame` extracts it, caches it under `~/.tame/auth/`, and hands it to the container at start, so there's no copying tokens into env files and no secrets baked into images. On Linux, or with no Keychain entry, it falls back to `ANTHROPIC_API_KEY` or a manual login. Which agent image runs where is config (an `AgentResolver` keyed by agent name) rather than a flag you have to remember.

A good chunk of the typing was agent-driven, which is the whole point: build the factory that builds the cars. The bit I did was decide what a session is, what it reports, where the boundary sits, and what the network looks like from inside it.

## if you're doing this

Put status in files under a bind mount and you never need a protocol. Decide the network from outside, at the kernel if you can, so the agent discovers that the world doesn't have npm in it today. Fetch credentials at start and never bake them in. And seed the onboarding config, or your first unattended run will spend the night on a welcome screen.
