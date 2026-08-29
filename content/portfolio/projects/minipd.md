---
title: "MiniPD coaching marketplace"
status: "archived"
start: 2020-02-13
end: 2022-08-25
tags: ["elixir", "phoenix", "postgres", "payments", "realtime", "aws", "leadership", "design-docs"]
highlights:
  - "Founding architect and tech lead, from empty repo to a 14-app Elixir umbrella split into product apps and reusable platform libraries"
  - "Personally built the payments path: idempotent Stripe Connect checkout with compensating refunds, payouts and reversals, and a double-entry ledger for school balances"
  - "Scheduling and booking engine, Twilio Video sessions, and in-house chat over Phoenix Channels after a documented build-vs-buy"
  - "GenStage event pub/sub driving email, audit and payment side-effects; role-based access control; SSO"
cv:
  include: true
  weight: 90
  highlights:
    - "Founding architect and tech lead: 14-app Elixir umbrella, Stripe Connect payments with a double-entry ledger, video and chat"
---

A two-sided marketplace connecting educators with professional-
development coaches. The parts I care most about are the ones that had
to be right: money moving through Stripe Connect with a ledger that
balances, and a booking engine that handles time zones without lying.
