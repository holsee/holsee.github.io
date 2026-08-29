---
title: "A Christmas of hex packages"
status: "paused"
start: 2025-12-17
end: 2025-12-27
links:
  - {label: "conjure on hex", url: "https://hex.pm/packages/conjure"}
  - {label: "deep_eval_ex on hex", url: "https://hex.pm/packages/deep_eval_ex"}
  - {label: "chatterbex on hex", url: "https://hex.pm/packages/chatterbex"}
tags: ["elixir", "oss", "llm", "agents", "evals"]
highlights:
  - "Three personal Elixir libraries written and published to hex in one December: conjure, deep_eval_ex and chatterbex"
  - "conjure implements Anthropic's Agent Skills for the BEAM: SKILL.md parsing, .skill packages, progressive disclosure, and one Session API formalised as a behaviour over local shell, Docker, the hosted Skills API and native Elixir modules, so moving a skill between backends does not touch the calling code"
  - "deep_eval_ex ports Confident AI's DeepEval to Elixir, keeping the test-case shape compatible with the Python original and the Apache-2.0 attribution explicit"
  - "conjure began as skillex over Christmas week, then went out under a new name and an Apache-2.0 licence"
  - "chatterbex, bindings for Resemble AI's Chatterbox text-to-speech with zero-shot voice cloning, was written on Christmas Day and on hex the day after"
cv:
  include: true
  weight: 65
  highlights:
    - "Wrote and published three Elixir libraries to hex over December 2025: conjure (Anthropic Agent Skills for the BEAM), deep_eval_ex (LLM evaluation, a port of DeepEval) and chatterbex (text-to-speech bindings)"
---

December 2025 went on personal Elixir libraries, written in my own time
for gaps I kept hitting in the AI work. Elixir had no LLM evaluation
harness I could find, so deep_eval_ex ports the metrics from Confident
AI's DeepEval and keeps the attribution explicit. Anthropic's Agent
Skills format is a good one and there was no Elixir implementation of
it, so I built that over Christmas week as skillex and re-released it as
conjure. The odd one out is chatterbex, text-to-speech bindings written
on Christmas Day and pushed to hex the morning after. There is no shared
code between the three; what they share is the fortnight and a hex
release.
