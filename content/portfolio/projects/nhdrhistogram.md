---
title: "NHdrHistogram: HdrHistogram ported to .NET"
status: "archived"
start: 2013-09-01
end: 2013-09-30
links:
  - {label: "Source", url: "https://github.com/holsee/NHdrHistogram"}
tags: ["oss", "dotnet", "algorithms"]
highlights:
  - "A .NET port of Gil Tene's HdrHistogram, written in September 2013 during the low-latency trading years"
  - "Recording in constant time at a fixed number of significant digits, so the tail of the latency distribution survives the measurement"
cv:
  include: true
  weight: 50
  highlights:
    - "Ported HdrHistogram to .NET (2013), from the low-latency trading years"
---

Porting something is how I make sure I actually understand it. In 2013 I
was working on trading systems and cared a great deal about measuring
latency without the measurement distorting what it measured, so I spent
a month of evenings in my own time writing Gil Tene's HdrHistogram out
in C#. Small repo, and what I got from it was the mechanism: constant
time recording at fixed significant-digit precision across the whole
range, which is what makes a histogram safe to put in a hot path. The
notes from Martin Thompson's lock-free algorithms course sit next to it
on my GitHub from the same stretch, which is a fair picture of what I
was reading then.
