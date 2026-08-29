---
title: "Account-linking and messaging service"
status: "archived"
start: 2019-05-21
end: 2022-02-16
tags: ["elixir", "phoenix", "postgres", "aws", "api-design", "distributed-systems"]
highlights:
  - "Sole architect and author of a platform that gave web applications with different authorisation providers an Apple Handoff-like capability for the same human user: a user-consented, secure link between two accounts, and messaging over it so the apps could act for that person and surface integrations across the pair"
  - "Cross-product account association and pull-based messaging, with the protocol documentation written in week one"
  - "OAuth-style three-legged account-link handshake; messaging with visibility timeouts and acknowledgement; idempotency, at-least-once delivery and no-system-time-in-protocols written down as principles"
  - "From week one: contract-first OpenAPI, property-based tests running 500–1,000 iterations in CI, full infrastructure as code"
  - "Wrote the Elixir and Ruby client libraries and a reference-implementation consumer; a load-test harness rounded out the platform"
cv:
  include: true
  weight: 90
  highlights:
    - "Sole architect of a platform giving web applications that share a human user but not an auth provider an Apple Handoff-style experience: a user-consented, secure link between accounts and messaging over it; OAuth-style handshake, visibility-timeout messaging, contract-first OpenAPI, property-based tests, full IaC, clients in two languages"
---

One person, one service, and the most careful protocol document I have
written. The idea was an Apple Handoff-style experience between web
applications that share a human user but not an auth provider: a link
the user consents to in both places, and a queue that carries messages
between the apps about that person from then on. Platforms are proven from
the consumer's side, so the clients, the reference consumer and the
load tests were part of the deliverable.
