---
title: "A realtime message-relay service"
status: "archived"
start: 2020-03-24
end: 2022-02-22
tags: ["elixir", "phoenix", "liveview", "realtime", "api-design"]
highlights:
  - "Sole author of service and client alike: a JWT-scoped pub/sub message relay over Phoenix Channels, the reusable replacement for a Rails product's ageing realtime transport"
  - "A scope/session model so messages fan out only within their scope; authorisation entirely by JWT"
  - "Shipped the service and its JavaScript client together, versioned to production"
cv:
  include: true
  weight: 48
---

Realtime as a service the rest of the platform could depend on:
connect, authenticate with a token, subscribe to a scope, and get every
message published into it. Service and browser client both mine.
