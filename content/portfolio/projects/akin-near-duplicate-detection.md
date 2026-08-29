---
title: "Coursework near-duplicate detection"
status: "active"
start: 2018-03-01
tags: ["elixir", "rust", "otp", "simhash", "aws", "design-docs"]
highlights:
  - "Originated the capability: wrote the 2018 RFC proposing near-duplicate detection for coursework submissions, and built the first service the same year (submit/similarity API, JWT auth, a CLI client)"
  - "2020: green-lit and specified with the IB; the spec validated the normalisation-plus-similarity approach as 100% effective against a real-world 20-document sample"
  - "2023: rebuilt it as a second-generation service on spirit_fingers, my own open-source Rust NIF; zero-knowledge design: only irreversible fingerprints are retained"
  - "2025–26: scale-up from polling to Broadway to Oban Pro, streaming downloads, PDFium text extraction, 100 MB uploads, capacity-tested with published results"
cv:
  include: true
  weight: 75
  highlights:
    - "Realised my own 2018 RFC as a service the same year, then rebuilt it in 2023 on my open-source Rust NIF and scaled it to 100 MB files"
---

I built this twice at work. A first service in 2018, the same year I
wrote the RFC; then a second-generation rebuild in 2023 on a Rust
library I wrote in my own time. The dependency is stated; the ownership
stays where it was.
