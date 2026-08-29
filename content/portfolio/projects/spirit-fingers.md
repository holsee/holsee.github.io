---
title: "spirit_fingers: SimHash for Elixir as a Rust NIF"
status: "paused"
start: 2018-05-16
end: 2025-10-22
links:
  - {label: "Source", url: "https://github.com/holsee/spirit_fingers"}
  - {label: "hex.pm", url: "https://hex.pm/packages/spirit_fingers"}
tags: ["elixir", "rust", "oss", "simhash", "algorithms"]
highlights:
  - "SimHash operations for Elixir with the hashing done in Rust through Rustler, flagged for the dirty CPU schedulers so a long hash over a large binary never blocks a normal BEAM scheduler"
  - "Roughly 276× the throughput of the two pure-Elixir alternatives at about 13,700× less memory on the same input, from a reproducible Benchee run; the only one of the three that survives multi-megabyte binaries"
  - "Became the fingerprinting engine inside a near-duplicate detection service"
cv:
  include: true
  weight: 95
  highlights:
    - "Wrote spirit_fingers, an Elixir SimHash library backed by a Rust NIF: kept on hex for seven years, roughly 276× faster than the pure-Elixir alternatives, and the engine inside a production duplicate-detection service"
---

The pure-Elixir SimHash libraries are fine on short strings and hopeless
on whole documents, so in my own time I put the hashing in Rust and
exposed it through Rustler. The detail that makes it safe in production
is the dirty CPU scheduler flag: a hash over a few megabytes takes as
long as it takes, and the BEAM's normal schedulers never see it. Seven
years of upkeep has mostly been Rustler version churn, plus the October
2025 release, where I pulled the upstream Rust crate into the repo with
its MIT attribution because it had gone unmaintained and I would rather
carry the code than the dependency. It later ended up as the
fingerprinting engine inside a duplicate-detection service I built at
work, which is about the nicest thing that can happen to a library you
wrote for yourself.
