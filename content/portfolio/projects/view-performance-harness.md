---
title: "Performance harness on my own headless-Chrome service"
status: "archived"
start: 2017-11-28
end: 2020-04-21
tags: ["elixir", "otp", "phoenix", "headless-chrome", "aws", "postgres"]
highlights:
  - "Sole author of my earliest work at Faria (from November 2017): a latency- and geography-aware performance-recording harness for an exam-systems product, driving real user scenarios over HTTP"
  - "Built on chroxy and chroxy_client (my own open-source headless-Chrome service), a personal library driving employer performance tests (dependency stated, ownership personal)"
  - "A Phoenix front end to run the scenarios and visualise the timings; runs stored in Postgres for regression tracking"
cv:
  include: true
  weight: 58
---

The first thing I built after joining, and the one that connects to my
open-source work most directly: a harness that records how long a
product actually takes for a user, network latency and all, by driving
a real browser through it. The browser pool is my own chroxy; the
timings land in Postgres so a regression has somewhere to show up.
