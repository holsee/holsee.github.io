---
title: "cherrypicker: named .localhost URLs for local dev servers"
status: "active"
start: 2026-08-20
links:
  - {label: "Source", url: "https://github.com/holsee/cherrypicker"}
tags: ["oss", "elixir", "static-site", "security"]
highlights:
  - "Stable named .localhost URLs for local dev servers: an app registers a name and a port with a loopback proxy, and nothing gets wrapped or launched on its behalf"
  - "Pure BEAM, with two runtime dependencies (Bandit and Finch): no Node toolchain to install and no root certificate authority to trust"
  - "Built over three days in August 2026 as a companion to Cherry, which speaks the same control API from about eighty lines of standard library instead of taking a dependency"
cv:
  include: true
  weight: 50
  highlights:
    - "cherrypicker: stable named .localhost URLs for local dev servers, written in Elixir with no Node toolchain and no root CA"
---

Six dev servers into an afternoon, no port number means anything, and
the one you bookmarked yesterday belongs to something else now. Vercel's
portless had the right shape of answer, named .localhost URLs with the
port lottery handled by a proxy, but getting it meant a global npm
install that self-elevates to bind port 443 and installs a locally
trusted root certificate authority, which is a lot of blast radius for a
convenience tool. So I spent three days in my own time building the same
idea on the BEAM: your dev server starts however it starts, one command
registers its name and port with a loopback proxy, and if no daemon is
running you get plain port URLs and carry on as before. It fell out of
the Cherry work in August 2026, and Cherry now registers with it when
you ask for a named URL.
