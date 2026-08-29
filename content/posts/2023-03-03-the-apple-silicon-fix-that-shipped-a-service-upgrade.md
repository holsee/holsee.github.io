---
title: "magic.h not found: fixing gen_magic upstream"
description: "A platform upgrade is a long tail of small blocking things. Mine got stuck on a C library that wouldn't compile on an M1 Mac, so the fix went upstream, and the most durable output of three weeks' work is two merged pull requests."
tags: [work, elixir, oss]
draft: true
---

I spent three weeks this year modernising a file-conversion service at work: the platform-upgrade kind of work, not the feature kind. Forty-one commits, and not one of them a feature: a runtime bump, dependency updates, the boring machinery of dragging a service's foundations up to current. The interesting thing about that kind of work is that its most lasting output usually isn't in the codebase you were paid to touch. Mine was two pull requests to a library I don't own, and they're the part worth writing down.

## A platform upgrade is a long tail of small blocking things

Nobody tells you this before your first big upgrade: it isn't one change, it's a hundred, and each one blocks the next. You can't fix the job scheduler until it compiles; it won't compile until the C dependency builds; the C dependency won't build until you've fixed an include path. So the work is a chain, and you can't parallelise a chain: you just walk it, and each link is individually trivial and collectively a fortnight.

The one worth telling is the link that wasn't mine to fix, and I fixed it anyway.

## The wall: a C library that wouldn't build on Apple Silicon

The service leans on [gen_magic](https://github.com/evadne/gen_magic), the Elixir wrapper around libmagic, the thing that tells you a file is really a PDF regardless of what its extension claims. It's a C port compiled at build time, and on an M1 or M2 Mac the build failed flat with `"magic.h not found"`. Every developer on Apple Silicon who wanted to run the service locally hit the same wall on their first `mix compile`, mine included.

The lazy move is to pin an old version, or keep a hacked local copy, or leave a `# TODO: broken on M1` and move on. I've done all three in my life and regretted each. The C problem was a Makefile that looked for `magic.h` in the wrong place on Homebrew's Apple Silicon layout, plus a use of the deprecated `:erlang.now/0`. Small. Genuinely small. But it lived upstream, in someone else's library, and the right place to fix an upstream problem is upstream.

## Send it up, small and reviewable

My first attempt was one pull request that bundled everything (the dependency bumps, the runtime upgrade and the fix all together), which is exactly the pull request a maintainer can't review. So I closed it and split it into two that they could:

- one that fixed the Makefile include path so `magic.h` is found on macOS and Apple Silicon;
- one that swapped the deprecated `:erlang.now/0` for `:os.timestamp/0`.

Both merged the next day, and gen_magic 1.1.0 went out with those two fixes as essentially its whole content. My service's dependency moved from a git reference pointing at a fork to `~> 1.1` from the package manager, which is where a dependency belongs. And every other person on an Apple Silicon Mac who uses that library got the fix for free, without knowing I existed.

That's the pattern I hold to, and it's the transferable part of the whole three weeks: when you hit a real problem in a dependency, fix it *there*, split it into changes a maintainer can actually read, get it released, and then depend on the release. It's slower than a local patch by about a day. It's faster than a local patch by however long you'd otherwise spend re-applying that patch every upgrade, forever, plus the compounding tax of being subtly forked from the world.

## Why the boring work is worth writing up

The service upgrade itself is unremarkable and I'll leave it at that: it's an internal thing, and "we moved to a newer runtime and a better job-pruning setup" is not a story. But the shape of it is worth internalising. A platform upgrade is a chain of small blocking tasks; you walk it link by link; and the single most valuable artefact you produce is often the fix you push *out* of your own codebase into the commons. The library has 27 stars and some tens of thousands of downloads. Two of my three weeks vanished into the repository nobody will ever see. The two hours that produced those PRs are on the internet, helping strangers, under my name. Guess which I'd rather have on the record.

## Where to look

- gen_magic (upstream OSS): pull requests #22 and #23 on [evadne/gen_magic](https://github.com/evadne/gen_magic), released as gen_magic 1.1.0.
