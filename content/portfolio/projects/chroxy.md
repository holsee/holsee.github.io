---
title: "chroxy: pooled headless Chrome over the DevTools protocol"
status: "archived"
start: 2018-03-19
end: 2021-01-19
links:
  - {label: "Source", url: "https://github.com/holsee/chroxy"}
  - {label: "hex.pm", url: "https://hex.pm/packages/chroxy"}
tags: ["elixir", "otp", "oss", "headless-chrome", "docker"]
highlights:
  - "Headless Chrome as a service: one endpoint hands back a WebSocket URI to a fresh page, proxied transparently, and the page is destroyed when the socket closes"
  - "A dedicated Elixir process per connection under a transparent TCP proxy, a hook behaviour tying browser lifecycle to the socket, and every Chrome browser supervised as an OS process under erlexec"
  - "266 stars and 26 forks; thirteen hex releases from 0.3.0 in May 2018 to 0.7.0 in January 2021, and still around 26 downloads a day years after the last one"
  - "Sole author, and reviewed and merged every community PR: six external contributors, among them a DockYard engineer, covering Docker support and permissions, a Cowboy 2.7 and dependency upgrade, and listener resilience"
cv:
  include: true
  weight: 95
  highlights:
    - "Wrote chroxy, an Elixir headless-Chrome proxy handing out raw DevTools connections from a supervised browser pool: 266 stars, thirteen hex releases, community contributors"
---

I needed thousands of concurrent browser scenarios with direct access to
the DevTools protocol, and the Elixir tools to hand were testing
frameworks that sat between me and the protocol. So I wrote chroxy in my
own time: ask for a connection, get a WebSocket URI, and a dedicated
process shuttles that socket to a Chrome page until either end goes
away, at which point the page goes too. Chrome itself runs as a
supervised OS process under erlexec and gets restarted when it falls
over, which it does. It went out under MIT six weeks after the first
commit, and community PRs kept arriving for years after I stopped adding
to it.
