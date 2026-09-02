---
title: "flywheel: high-performance data channels without NIFs"
description: "A bounded, back-pressuring channel over :atomics for the BEAM. Why an unbounded mailbox fails late and all at once, how a ring buffer with a claim cursor fixes it, and a worked futures-feed example where a ring's capacity turns out to be denominated in microseconds. Pre-release, and measured on one host."
tags: [personal, elixir, erlang, otp, realtime, distributed-systems]
---

Recently was I was toying with some code related to one of my recurring interest, data structures and algos, specifically histograms in the context of a Radix Sorts - and the inspiration for the subject of this post struck when I was reading up on BEAM [atomics](https://www.erlang.org/doc/apps/erts/atomics.html). Back in 2013 I took Martin Thompson's training on high-performance lock-free concurrent data structures, and it was superb: mechanical sympathy, cache lines, the Disruptor. It has been rattling around in my head ever since. Then OTP 21.2 added the `atomics` module, a fixed-size array of 64-bit integers with atomic operations over it, and that is an escape hatch out of the higher-level constructs and down much closer to the metal. I wanted to see how far it goes. Out fell flywheel, a high-performance fixed size data channel with back-pressure inspired by the disruptor pattern.

> Also note, I am making some assumptions based on what I _know_ and rolling on gut in many areas - many micro-optmisations to be found and the fun is in the details.  Also, I need to setup a proper test bench, which means the numbers in this post are more relative than maxed out. But compared to the existing alternatives, this ring buffer goes brrr.

The short version: it moves 64-bit integers between BEAM processes through a fixed-size ring buffer built on `:atomics`. Payloads live off-heap in a shared array, so there is no copying and no per-message allocation, and no process's garbage collector ever sees them. The mailbox is still there, but it carries one wake signal per batch rather than one message per item. And because the buffer is bounded, a producer that outruns its consumer gets back-pressure, the one thing `send/2` cannot give you.

It is deliberately not a general queue. Signed int64 payloads only: packed structs, timestamps, ids, enum tags. No arbitrary terms, no node boundaries, no selective receive.

## using it

A ring is a term you make and hand to producers. Capacity is a power of two:

```elixir
ring = Flywheel.new(1024)
:ok = Flywheel.push(ring, 42)
{:ok, 42} = Flywheel.pop(ring)
```

The process that calls `new/2` becomes the consumer, the one woken when a producer publishes, unless `:consumer` says otherwise. The term itself is safe to send to other processes: they all end up pointing at the same shared array, which is what makes the transport free of copying.

In anything real the consumer is a supervised process, and `Flywheel.Channel` is that process:

```elixir
{:ok, ch} = Flywheel.Channel.start_link(capacity: 8192, handler: &IO.inspect/1)
ring = Flywheel.Channel.ring(ch)

# from any number of other processes
Flywheel.push_wait(ring, 42)
```

Producers hold the ring and write into shared memory directly. They never send the channel a message and never appear in its mailbox, which is the whole point: it carries one wake per batch rather than one message per item.

### the two pushes are the policy

There are two ways to offer an item, and choosing between them is the only real design decision the library asks of you.

```elixir
# refuses when full, never blocks
case Flywheel.push(ring, packed) do
  :ok -> :ok
  {:error, :full} -> count_a_drop()
end

# waits for space, up to a timeout you choose
case Flywheel.push_wait(ring, packed, 100) do
  :ok -> :ok
  {:error, :timeout} -> trip_the_breaker()
end
```

`{:error, :full}` and `{:error, :timeout}` are the return values `send/2` has no way to produce, and that is the entire difference between the two transports. A refused `push/2` has not advanced the cursor, so no sequence is burnt and the consumer never has to wait one out.

### draining without allocating

`pop_batch/2` is the convenient drain, and it allocates: one cons cell per item plus the reverse inside it, all on the consumer's heap, which puts back exactly the collection pressure the ring exists to remove. For a hot loop, fold straight into an accumulator instead:

```elixir
{acc, consumed, skipped} =
  Flywheel.fold(ring, 4096, acc, fn item, acc -> apply_update(acc, item) end)
```

A channel takes the same thing as a handler, `{:fold, fun, acc0}`, and carries the accumulator across drain passes. The repo's own A/B at 1,000 producers moved the fold drain from 3,147 to 4,596 Kmsg/s, a 46% gain, with minor GCs collapsing from 8,347 to between 50 and 74, while the list drain did not move at all. The fold runs on the channel process, so it has to be quick and it has to be total: a slow one stalls the drain and back-pressures every producer through the bounded capacity, and one that raises crashes the channel that owns the ring.

## the failure mode you already know

Erlang mailboxes are unbounded. A consumer that falls behind does not fail; it accumulates. The failure arrives later, all at once, from the OOM killer, with the latency already ruined long before anyone noticed.

Under a flood of 100 producers pushing 500k items unthrottled, that shape looks like this. Median of nine interleaved rounds, i5-13600K, OTP 29, in a container with pinned cores. Relative findings, not portable numbers:

| | `off_heap` mailbox | flywheel | |
|---|---:|---:|---|
| throughput (Kmsg/s) | 4,461 | **7,020** | 1.57× (9/9 rounds, p = 0.004) |
| p50 latency | 49.6 ms | **518 µs** | 96× |
| p99.9 latency | 74.1 ms | **2.3 ms** | 32× |
| peak memory | 52.6 MB | **1.7 MB** | 30× |
| peak items outstanding | 472,170 | **2,694** | 175× |
| minor GCs | 5,128 | **22** | 233× |

Those are not six results, they are one. The mailbox reaches its throughput by letting most of the run pile into a queue with no upper bound, and that backlog *is* the 49.6 ms median and *is* the 52.6 MB. The ring holds about 2,700 items because it is not allowed to hold more, and that is precisely why its median is sub-millisecond.

Push the fan-in to 1,000 producers into the same consumer and nothing about the story changes: 5,899 Kmsg/s against 3,803, again winning all nine rounds, medians of 673 µs against 51.2 ms, 5.7 MB against 53.4 MB. Boundedness is not a low-fan-in trick.

## the ring

A ring is `capacity` slots and two monotonically increasing cursors. The consumer's cursor never passes the producer's; the producer's may never get more than `capacity` ahead of the consumer's. Slot index is just `seq band mask`, which is why capacity has to be a power of two.

<!-- fig:ring -->
<figure class="diagram">
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 760 395" role="img" aria-label="Two ring buffers of sixteen slots: one with room, the producer cursor eight slots ahead of the consumer; one full, the producer having lapped the ring, where push returns error full and push_wait yields" style="width:100%;height:auto;max-width:760px;font-family:ui-monospace,Menlo,Consolas,monospace;font-size:13px;color:var(--color-fg,currentColor)">
<defs><marker id="fw-ring-ah" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0L10 5L0 10z" fill="currentColor"/></marker></defs>
<text x="180" y="26" text-anchor="middle" font-size="12" fill="currentColor" font-weight="bold">room: producer ahead of consumer</text>
<g transform="rotate(11.25 180 200)"><rect x="163" y="75" width="34" height="26" fill="var(--color-surface, #e7e3d7)" stroke="currentColor" stroke-width="1"/></g>
<g transform="rotate(33.75 180 200)"><rect x="163" y="75" width="34" height="26" fill="var(--color-surface, #e7e3d7)" stroke="currentColor" stroke-width="1"/></g>
<g transform="rotate(56.25 180 200)"><rect x="163" y="75" width="34" height="26" fill="var(--color-accent, #b2570a)" fill-opacity="0.45" stroke="currentColor" stroke-width="1"/></g>
<g transform="rotate(78.75 180 200)"><rect x="163" y="75" width="34" height="26" fill="var(--color-accent, #b2570a)" fill-opacity="0.45" stroke="currentColor" stroke-width="1"/></g>
<g transform="rotate(101.25 180 200)"><rect x="163" y="75" width="34" height="26" fill="var(--color-accent, #b2570a)" fill-opacity="0.45" stroke="currentColor" stroke-width="1"/></g>
<g transform="rotate(123.75 180 200)"><rect x="163" y="75" width="34" height="26" fill="var(--color-accent, #b2570a)" fill-opacity="0.45" stroke="currentColor" stroke-width="1"/></g>
<g transform="rotate(146.25 180 200)"><rect x="163" y="75" width="34" height="26" fill="var(--color-accent, #b2570a)" fill-opacity="0.45" stroke="currentColor" stroke-width="1"/></g>
<g transform="rotate(168.75 180 200)"><rect x="163" y="75" width="34" height="26" fill="var(--color-accent, #b2570a)" fill-opacity="0.45" stroke="currentColor" stroke-width="1"/></g>
<g transform="rotate(191.25 180 200)"><rect x="163" y="75" width="34" height="26" fill="var(--color-accent, #b2570a)" fill-opacity="0.45" stroke="currentColor" stroke-width="1"/></g>
<g transform="rotate(213.75 180 200)"><rect x="163" y="75" width="34" height="26" fill="var(--color-accent, #b2570a)" fill-opacity="0.45" stroke="currentColor" stroke-width="1"/></g>
<g transform="rotate(236.25 180 200)"><rect x="163" y="75" width="34" height="26" fill="var(--color-surface, #e7e3d7)" stroke="currentColor" stroke-width="1"/></g>
<g transform="rotate(258.75 180 200)"><rect x="163" y="75" width="34" height="26" fill="var(--color-surface, #e7e3d7)" stroke="currentColor" stroke-width="1"/></g>
<g transform="rotate(281.25 180 200)"><rect x="163" y="75" width="34" height="26" fill="var(--color-surface, #e7e3d7)" stroke="currentColor" stroke-width="1"/></g>
<g transform="rotate(303.75 180 200)"><rect x="163" y="75" width="34" height="26" fill="var(--color-surface, #e7e3d7)" stroke="currentColor" stroke-width="1"/></g>
<g transform="rotate(326.25 180 200)"><rect x="163" y="75" width="34" height="26" fill="var(--color-surface, #e7e3d7)" stroke="currentColor" stroke-width="1"/></g>
<g transform="rotate(348.75 180 200)"><rect x="163" y="75" width="34" height="26" fill="var(--color-surface, #e7e3d7)" stroke="currentColor" stroke-width="1"/></g>
<line x1="289.6" y1="90.4" x2="272.5" y2="107.5" stroke="currentColor" stroke-width="1.5" marker-end="url(#fw-ring-ah)"/>
<text x="298" y="80" text-anchor="start" font-size="11" fill="currentColor">consumer cursor</text>
<text x="298" y="94" text-anchor="start" font-size="11" fill="currentColor" opacity="0.75">next slot to drain</text>
<line x1="70.4" y1="309.6" x2="87.5" y2="292.5" stroke="currentColor" stroke-width="1.5" marker-end="url(#fw-ring-ah)"/>
<text x="14" y="330" text-anchor="start" font-size="11" fill="currentColor">producer cursor</text>
<text x="14" y="344" text-anchor="start" font-size="11" fill="currentColor" opacity="0.75">next slot to claim</text>
<text x="180" y="196" text-anchor="middle" font-size="14" fill="currentColor" font-weight="bold">8 of 16</text>
<text x="180" y="213" text-anchor="middle" font-size="11" fill="currentColor" opacity="0.75">outstanding</text>
<text x="180" y="366" text-anchor="middle" font-size="11" fill="currentColor">push/2 and push_wait/3 both return :ok</text>
<text x="560" y="26" text-anchor="middle" font-size="12" fill="currentColor" font-weight="bold">full: the producer has lapped the ring</text>
<g transform="rotate(11.25 560 200)"><rect x="543" y="75" width="34" height="26" fill="#d1495b" fill-opacity="0.45" stroke="currentColor" stroke-width="1"/></g>
<g transform="rotate(33.75 560 200)"><rect x="543" y="75" width="34" height="26" fill="#d1495b" fill-opacity="0.45" stroke="currentColor" stroke-width="1"/></g>
<g transform="rotate(56.25 560 200)"><rect x="543" y="75" width="34" height="26" fill="#d1495b" fill-opacity="0.45" stroke="currentColor" stroke-width="1"/></g>
<g transform="rotate(78.75 560 200)"><rect x="543" y="75" width="34" height="26" fill="#d1495b" fill-opacity="0.45" stroke="currentColor" stroke-width="1"/></g>
<g transform="rotate(101.25 560 200)"><rect x="543" y="75" width="34" height="26" fill="#d1495b" fill-opacity="0.45" stroke="currentColor" stroke-width="1"/></g>
<g transform="rotate(123.75 560 200)"><rect x="543" y="75" width="34" height="26" fill="#d1495b" fill-opacity="0.45" stroke="currentColor" stroke-width="1"/></g>
<g transform="rotate(146.25 560 200)"><rect x="543" y="75" width="34" height="26" fill="#d1495b" fill-opacity="0.45" stroke="currentColor" stroke-width="1"/></g>
<g transform="rotate(168.75 560 200)"><rect x="543" y="75" width="34" height="26" fill="#d1495b" fill-opacity="0.45" stroke="currentColor" stroke-width="1"/></g>
<g transform="rotate(191.25 560 200)"><rect x="543" y="75" width="34" height="26" fill="#d1495b" fill-opacity="0.45" stroke="currentColor" stroke-width="1"/></g>
<g transform="rotate(213.75 560 200)"><rect x="543" y="75" width="34" height="26" fill="#d1495b" fill-opacity="0.45" stroke="currentColor" stroke-width="1"/></g>
<g transform="rotate(236.25 560 200)"><rect x="543" y="75" width="34" height="26" fill="#d1495b" fill-opacity="0.45" stroke="currentColor" stroke-width="1"/></g>
<g transform="rotate(258.75 560 200)"><rect x="543" y="75" width="34" height="26" fill="#d1495b" fill-opacity="0.45" stroke="currentColor" stroke-width="1"/></g>
<g transform="rotate(281.25 560 200)"><rect x="543" y="75" width="34" height="26" fill="#d1495b" fill-opacity="0.45" stroke="currentColor" stroke-width="1"/></g>
<g transform="rotate(303.75 560 200)"><rect x="543" y="75" width="34" height="26" fill="#d1495b" fill-opacity="0.45" stroke="currentColor" stroke-width="1"/></g>
<g transform="rotate(326.25 560 200)"><rect x="543" y="75" width="34" height="26" fill="#d1495b" fill-opacity="0.45" stroke="currentColor" stroke-width="1"/></g>
<g transform="rotate(348.75 560 200)"><rect x="543" y="75" width="34" height="26" fill="#d1495b" fill-opacity="0.45" stroke="currentColor" stroke-width="1"/></g>
<line x1="669.6" y1="309.6" x2="652.5" y2="292.5" stroke="currentColor" stroke-width="1.5" marker-end="url(#fw-ring-ah)"/>
<text x="560" y="196" text-anchor="middle" font-size="14" fill="currentColor" font-weight="bold">16 of 16</text>
<text x="560" y="213" text-anchor="middle" font-size="11" fill="currentColor" opacity="0.75">both cursors here</text>
<text x="596" y="330" text-anchor="start" font-size="11" fill="currentColor">producer = consumer + capacity</text>
<text x="596" y="344" text-anchor="start" font-size="11" fill="currentColor" opacity="0.75">so the ring reads as full</text>
<text x="560" y="366" text-anchor="middle" font-size="11" fill="currentColor">push/2 → {:error, :full}</text>
<text x="560" y="381" text-anchor="middle" font-size="11" fill="currentColor">push_wait/3 → yields, never spins</text>
</svg>
<figcaption>Sixteen slots, two cursors, and the entire policy question. The right-hand ring is the interesting one, because there is no state after it: a bounded buffer that fills has exactly three options (lose data, grow without bound, or push back), and the whole library is an argument for the third.</figcaption>
</figure>

The waiting is the part worth dwelling on. `push_wait/3` yields the scheduler; it never spins. A producer that burns its time slice waiting would be starving the very consumer it is waiting for, which is the failure this design exists to avoid. That single constraint is why this is a re-derivation of the LMAX Disruptor's ideas rather than a port of it: the Disruptor's wait strategies assume the waiting thread owns a core, and on the BEAM it emphatically does not.

## the claim protocol

With one producer, the cursor advance *is* the publish: write the payload, bump the cursor, done, two atomic operations per item. With many producers you need one more thing, because publication is no longer in order.

<!-- fig:claim -->
<figure class="diagram">
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 760 335" role="img" aria-label="Multi-producer claim and publish: three producers compare-exchange one cursor, then write payloads out of order, with availability stamps letting the consumer advance only over a contiguous published prefix" style="width:100%;height:auto;max-width:760px;font-family:ui-monospace,Menlo,Consolas,monospace;font-size:13px;color:var(--color-fg,currentColor)">
<defs><marker id="fw-claim-ah" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0L10 5L0 10z" fill="currentColor"/></marker></defs>
<text x="10" y="22" text-anchor="start" font-size="13" fill="currentColor" font-weight="bold">1. claim: a bounded compare-exchange on one cursor</text>
<rect x="20" y="44" width="60" height="26" fill="#2e86ab" fill-opacity="0.35" stroke="currentColor" stroke-width="1"/>
<text x="50" y="62" text-anchor="middle" font-size="12" fill="currentColor">P1</text>
<rect x="20" y="76" width="60" height="26" fill="#3a9d5d" fill-opacity="0.35" stroke="currentColor" stroke-width="1"/>
<text x="50" y="94" text-anchor="middle" font-size="12" fill="currentColor">P2</text>
<rect x="20" y="108" width="60" height="26" fill="#9b5de5" fill-opacity="0.35" stroke="currentColor" stroke-width="1"/>
<text x="50" y="126" text-anchor="middle" font-size="12" fill="currentColor">P3</text>
<line x1="82" y1="57" x2="196" y2="82" stroke="currentColor" stroke-width="1" marker-end="url(#fw-claim-ah)"/>
<line x1="82" y1="89" x2="196" y2="89" stroke="currentColor" stroke-width="1" marker-end="url(#fw-claim-ah)"/>
<line x1="82" y1="121" x2="196" y2="96" stroke="currentColor" stroke-width="1" marker-end="url(#fw-claim-ah)"/>
<rect x="200" y="68" width="110" height="40" fill="var(--color-accent, #b2570a)" fill-opacity="0.3" stroke="currentColor" stroke-width="1.5"/>
<text x="255" y="60" text-anchor="middle" font-size="10" fill="currentColor" opacity="0.75">producer cursor</text>
<text x="255" y="96" text-anchor="middle" font-size="16" fill="currentColor" font-weight="bold">44</text>
<text x="330" y="70" text-anchor="start" font-size="11" fill="currentColor">compare_exchange(44 → 45)</text>
<text x="330" y="88" text-anchor="start" font-size="11" fill="currentColor" opacity="0.8">One winner. The losers re-read the cursor and retry, so a</text>
<text x="330" y="104" text-anchor="start" font-size="11" fill="currentColor" opacity="0.8">claim is never burnt, which fetch-and-add cannot promise.</text>
<text x="10" y="162" text-anchor="start" font-size="13" fill="currentColor" font-weight="bold">2. write the payload, then stamp availability</text>
<text x="130" y="188" text-anchor="end" font-size="10" fill="currentColor" opacity="0.75">seq</text>
<text x="130" y="216" text-anchor="end" font-size="10" fill="currentColor" opacity="0.75">dat</text>
<text x="130" y="250" text-anchor="end" font-size="10" fill="currentColor" opacity="0.75">av</text>
<text x="171" y="188" text-anchor="middle" font-size="11" fill="currentColor">40</text>
<rect x="140" y="196" width="62" height="30" fill="var(--color-accent, #b2570a)" fill-opacity="0.45" stroke="currentColor" stroke-width="1"/>
<text x="171" y="216" text-anchor="middle" font-size="12" fill="currentColor">7001</text>
<text x="171" y="250" text-anchor="middle" font-size="11" fill="currentColor">41</text>
<text x="233" y="188" text-anchor="middle" font-size="11" fill="currentColor">41</text>
<rect x="202" y="196" width="62" height="30" fill="var(--color-accent, #b2570a)" fill-opacity="0.45" stroke="currentColor" stroke-width="1"/>
<text x="233" y="216" text-anchor="middle" font-size="12" fill="currentColor">7002</text>
<text x="233" y="250" text-anchor="middle" font-size="11" fill="currentColor">42</text>
<text x="295" y="188" text-anchor="middle" font-size="11" fill="currentColor">42</text>
<rect x="264" y="196" width="62" height="30" fill="#d1495b" fill-opacity="0.3" stroke="currentColor" stroke-width="1.5" stroke-dasharray="4 3"/>
<text x="295" y="216" text-anchor="middle" font-size="12" fill="currentColor" opacity="0.6">—</text>
<text x="295" y="250" text-anchor="middle" font-size="10" fill="currentColor" opacity="0.7">unwritten</text>
<text x="357" y="188" text-anchor="middle" font-size="11" fill="currentColor">43</text>
<rect x="326" y="196" width="62" height="30" fill="var(--color-accent, #b2570a)" fill-opacity="0.45" stroke="currentColor" stroke-width="1"/>
<text x="357" y="216" text-anchor="middle" font-size="12" fill="currentColor">7004</text>
<text x="357" y="250" text-anchor="middle" font-size="11" fill="currentColor">44</text>
<text x="419" y="188" text-anchor="middle" font-size="11" fill="currentColor">44</text>
<rect x="388" y="196" width="62" height="30" fill="var(--color-surface, #e7e3d7)" stroke="currentColor" stroke-width="1"/>
<text x="481" y="188" text-anchor="middle" font-size="11" fill="currentColor">45</text>
<rect x="450" y="196" width="62" height="30" fill="var(--color-surface, #e7e3d7)" stroke="currentColor" stroke-width="1"/>
<text x="543" y="188" text-anchor="middle" font-size="11" fill="currentColor">46</text>
<rect x="512" y="196" width="62" height="30" fill="var(--color-surface, #e7e3d7)" stroke="currentColor" stroke-width="1"/>
<text x="605" y="188" text-anchor="middle" font-size="11" fill="currentColor">47</text>
<rect x="574" y="196" width="62" height="30" fill="var(--color-surface, #e7e3d7)" stroke="currentColor" stroke-width="1"/>
<line x1="171" y1="278" x2="171" y2="232" stroke="currentColor" stroke-width="1.5" marker-end="url(#fw-claim-ah)"/>
<text x="171" y="292" text-anchor="middle" font-size="10" fill="currentColor">consumer</text>
<line x1="264" y1="176" x2="264" y2="266" stroke="#d1495b" stroke-width="1.5" stroke-dasharray="5 4"/>
<text x="276" y="308" text-anchor="start" font-size="11" fill="currentColor">Delivery stops at the barrier: 42 is claimed but unstamped, so 43 waits even though it is written.</text>
<text x="276" y="324" text-anchor="start" font-size="11" fill="currentColor" opacity="0.8">The stamp for sequence S is S+1, which is what distinguishes one lap of the ring from the next.</text>
</svg>
<figcaption>Under multiple producers the cursor alone cannot tell the consumer a slot is ready, because P3 may finish writing 43 before P2 finishes writing 42. A second array of availability stamps carries that information, and the consumer only ever advances over a contiguous published prefix.</figcaption>
</figure>

The claim is a compare-exchange rather than a fetch-and-add, and that is a deliberate trade of some cost for a property. Fetch-and-add is cheaper but cannot signal its own failure: a producer that claims a sequence and then finds the ring full has already advanced the cursor and cannot mark the slot, because the slot still holds a live item from the previous lap. The consumer could then only recover by waiting out a deadline, one sequence at a time, which under sustained overload becomes the steady state rather than a rare fault. A CAS claim cannot reach that state.

The one hazard the stamps exist to cover is a producer that dies between claiming and writing. That is real, and the cost is bounded rather than eliminated: after `skip_after_us` (50 ms by default) the consumer steps over the sequence and counts a drop.

Everything else about the layout is cache mechanics. Four separate atomics arrays rather than one, because every atomics operation bounds-checks against the array header, so a hot cell at a low index dirties a line that every concurrent operation must re-fetch; `header_slack` keeps the hot cells clear of it, and that turned out to matter more than padding between them. The `pushed` and `popped` counts are derived from the cursors rather than counted, because a counter increment per item is roughly 50% overhead on a two-operation push to record something the cursors already know.

## sharding: when one cursor is the problem

Every producer in a single ring compare-exchanges the same word. That word lives in one cache line, and a line can only be written by one core at a time, so past a handful of producers they spend their time passing it between them. The contention table above shows it: a single ring peaks at four senders and falls away from there.

`Flywheel.Shards` removes the sharing by giving each producer its own ring. It is the single writer principle, applied to the cursor.

<!-- fig:shards -->
<figure class="diagram">
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 760 282" role="img" aria-label="Left: four producers all compare-exchange one cursor word inside a single cache line. Right: four producers each bound to their own ring and their own cursor, sharing nothing" style="width:100%;height:auto;max-width:760px;font-family:ui-monospace,Menlo,Consolas,monospace;font-size:13px;color:var(--color-fg,currentColor)">
<defs><marker id="fw-sh-ah" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0L10 5L0 10z" fill="currentColor"/></marker></defs>
<text x="10" y="20" text-anchor="start" font-size="12.5" fill="currentColor" font-weight="bold">one ring: every producer writes the same word</text>
<rect x="16" y="48" width="50" height="24" fill="#2e86ab" fill-opacity="0.35" stroke="currentColor" stroke-width="1"/>
<text x="41" y="65" text-anchor="middle" font-size="11" fill="currentColor">P1</text>
<rect x="16" y="80" width="50" height="24" fill="#3a9d5d" fill-opacity="0.35" stroke="currentColor" stroke-width="1"/>
<text x="41" y="97" text-anchor="middle" font-size="11" fill="currentColor">P2</text>
<rect x="16" y="112" width="50" height="24" fill="#9b5de5" fill-opacity="0.35" stroke="currentColor" stroke-width="1"/>
<text x="41" y="129" text-anchor="middle" font-size="11" fill="currentColor">P3</text>
<rect x="16" y="144" width="50" height="24" fill="#1b998b" fill-opacity="0.35" stroke="currentColor" stroke-width="1"/>
<text x="41" y="161" text-anchor="middle" font-size="11" fill="currentColor">P4</text>
<line x1="68" y1="60" x2="172" y2="110" stroke="currentColor" stroke-width="1" marker-end="url(#fw-sh-ah)"/>
<line x1="68" y1="92" x2="172" y2="116" stroke="currentColor" stroke-width="1" marker-end="url(#fw-sh-ah)"/>
<line x1="68" y1="124" x2="172" y2="122" stroke="currentColor" stroke-width="1" marker-end="url(#fw-sh-ah)"/>
<line x1="68" y1="156" x2="172" y2="128" stroke="currentColor" stroke-width="1" marker-end="url(#fw-sh-ah)"/>
<rect x="168" y="84" width="146" height="70" fill="none" stroke="#d1495b" stroke-width="1.5" stroke-dasharray="5 4"/>
<rect x="184" y="102" width="114" height="34" fill="var(--color-accent, #b2570a)" fill-opacity="0.4" stroke="currentColor" stroke-width="1.5"/>
<text x="241" y="98" text-anchor="middle" font-size="10" fill="currentColor" opacity="0.75">producer cursor</text>
<text x="241" y="126" text-anchor="middle" font-size="15" fill="currentColor" font-weight="bold">44</text>
<text x="241" y="172" text-anchor="middle" font-size="10.5" fill="#d1495b">one cache line, one core at a time</text>
<text x="16" y="206" text-anchor="start" font-size="11" fill="currentColor" opacity="0.85">Past a few producers most of the time goes into</text>
<text x="16" y="222" text-anchor="start" font-size="11" fill="currentColor" opacity="0.85">passing that one line between cores.</text>
<line x1="356" y1="34" x2="356" y2="230" stroke="currentColor" stroke-width="1" opacity="0.25"/>
<text x="392" y="20" text-anchor="start" font-size="12.5" fill="currentColor" font-weight="bold">four shards: one ring each, nothing shared</text>
<rect x="392" y="48" width="50" height="24" fill="#2e86ab" fill-opacity="0.35" stroke="currentColor" stroke-width="1"/>
<text x="417" y="65" text-anchor="middle" font-size="11" fill="currentColor">P1</text>
<line x1="444" y1="60" x2="482" y2="60" stroke="currentColor" stroke-width="1" marker-end="url(#fw-sh-ah)"/>
<rect x="486" y="48" width="34" height="24" fill="var(--color-accent, #b2570a)" fill-opacity="0.4" stroke="currentColor" stroke-width="1"/>
<rect x="524" y="48" width="220" height="24" fill="#2e86ab" fill-opacity="0.14" stroke="currentColor" stroke-width="1"/>
<text x="634" y="65" text-anchor="middle" font-size="10" fill="currentColor" opacity="0.8">shard 0</text>
<rect x="392" y="80" width="50" height="24" fill="#3a9d5d" fill-opacity="0.35" stroke="currentColor" stroke-width="1"/>
<text x="417" y="97" text-anchor="middle" font-size="11" fill="currentColor">P2</text>
<line x1="444" y1="92" x2="482" y2="92" stroke="currentColor" stroke-width="1" marker-end="url(#fw-sh-ah)"/>
<rect x="486" y="80" width="34" height="24" fill="var(--color-accent, #b2570a)" fill-opacity="0.4" stroke="currentColor" stroke-width="1"/>
<rect x="524" y="80" width="220" height="24" fill="#3a9d5d" fill-opacity="0.14" stroke="currentColor" stroke-width="1"/>
<text x="634" y="97" text-anchor="middle" font-size="10" fill="currentColor" opacity="0.8">shard 1</text>
<rect x="392" y="112" width="50" height="24" fill="#9b5de5" fill-opacity="0.35" stroke="currentColor" stroke-width="1"/>
<text x="417" y="129" text-anchor="middle" font-size="11" fill="currentColor">P3</text>
<line x1="444" y1="124" x2="482" y2="124" stroke="currentColor" stroke-width="1" marker-end="url(#fw-sh-ah)"/>
<rect x="486" y="112" width="34" height="24" fill="var(--color-accent, #b2570a)" fill-opacity="0.4" stroke="currentColor" stroke-width="1"/>
<rect x="524" y="112" width="220" height="24" fill="#9b5de5" fill-opacity="0.14" stroke="currentColor" stroke-width="1"/>
<text x="634" y="129" text-anchor="middle" font-size="10" fill="currentColor" opacity="0.8">shard 2</text>
<rect x="392" y="144" width="50" height="24" fill="#1b998b" fill-opacity="0.35" stroke="currentColor" stroke-width="1"/>
<text x="417" y="161" text-anchor="middle" font-size="11" fill="currentColor">P4</text>
<line x1="444" y1="156" x2="482" y2="156" stroke="currentColor" stroke-width="1" marker-end="url(#fw-sh-ah)"/>
<rect x="486" y="144" width="34" height="24" fill="var(--color-accent, #b2570a)" fill-opacity="0.4" stroke="currentColor" stroke-width="1"/>
<rect x="524" y="144" width="220" height="24" fill="#1b998b" fill-opacity="0.14" stroke="currentColor" stroke-width="1"/>
<text x="634" y="161" text-anchor="middle" font-size="10" fill="currentColor" opacity="0.8">shard 3</text>
<text x="392" y="206" text-anchor="start" font-size="11" fill="currentColor" opacity="0.85">A pid hash picks the shard. Two producers can land on</text>
<text x="392" y="222" text-anchor="start" font-size="11" fill="currentColor" opacity="0.85">the same one, which is unbalanced rather than wrong.</text>
<line x1="16" y1="244" x2="744" y2="244" stroke="currentColor" stroke-width="1" opacity="0.2"/>
<text x="380" y="266" text-anchor="middle" font-size="11.5" fill="currentColor">16 senders, equal total memory: <tspan font-weight="bold">11,851</tspan> Kmsg/s on one ring against <tspan font-weight="bold">18,808</tspan> on four shards.</text>
</svg>
<figcaption>A single ring puts every producer on one compare-exchange against one word, and that word cannot be written by two cores at once. Sharding gives each producer its own ring and its own cursor, so the cores stop fighting over a cache line. Every shard is still an mpsc ring, which is what makes a hash collision merely unbalanced: two producers on one shard contend with each other rather than with everybody, and a shard with a single producer never contends at all.</figcaption>
</figure>

The assignment is a hash of the producer's pid, cached in the process dictionary, because `erlang:phash2/2` costs more than the push it is routing. The API is the one you already have:

```elixir
shards = Flywheel.Shards.new(4, 4096)

# from any number of producer processes
:ok = Flywheel.Shards.push_wait(shards, 1_234_567)

# in the consumer
{acc, count, _skipped} = Flywheel.Shards.fold(shards, 4096, 0, &(&1 + &2))
```

### what the consumer pays for it

Producers stop contending, and the bill lands on the other end. One consumer now has to visit N rings instead of one.

<!-- fig:shard-drain -->
<figure class="diagram">
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 760 292" role="img" aria-label="One consumer walking four shard rings round robin from a rotating start, arming every shard and waking on a publish from any of them" style="width:100%;height:auto;max-width:760px;font-family:ui-monospace,Menlo,Consolas,monospace;font-size:13px;color:var(--color-fg,currentColor)">
<defs><marker id="fw-sd-ah" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0L10 5L0 10z" fill="currentColor"/></marker></defs>
<text x="10" y="20" text-anchor="start" font-size="12.5" fill="currentColor" font-weight="bold">one consumer, N rings: round robin from a rotating start</text>
<text x="98" y="44" text-anchor="middle" font-size="10" fill="currentColor" opacity="0.8">shard 0</text>
<rect x="26" y="52" width="144" height="40" fill="none" stroke="currentColor" stroke-width="1.5"/>
<rect x="34" y="60" width="30" height="24" fill="var(--color-accent, #b2570a)" fill-opacity="0.45" stroke="currentColor" stroke-width="1"/>
<rect x="68" y="60" width="30" height="24" fill="var(--color-accent, #b2570a)" fill-opacity="0.45" stroke="currentColor" stroke-width="1"/>
<rect x="102" y="60" width="30" height="24" fill="var(--color-surface, #e7e3d7)" stroke="currentColor" stroke-width="1"/>
<rect x="136" y="60" width="26" height="24" fill="var(--color-surface, #e7e3d7)" stroke="currentColor" stroke-width="1"/>
<text x="278" y="44" text-anchor="middle" font-size="10" fill="currentColor" opacity="0.8">shard 1</text>
<rect x="206" y="52" width="144" height="40" fill="none" stroke="currentColor" stroke-width="1.5"/>
<rect x="214" y="60" width="30" height="24" fill="var(--color-surface, #e7e3d7)" stroke="currentColor" stroke-width="1"/>
<rect x="248" y="60" width="30" height="24" fill="var(--color-surface, #e7e3d7)" stroke="currentColor" stroke-width="1"/>
<rect x="282" y="60" width="30" height="24" fill="var(--color-surface, #e7e3d7)" stroke="currentColor" stroke-width="1"/>
<rect x="316" y="60" width="26" height="24" fill="var(--color-surface, #e7e3d7)" stroke="currentColor" stroke-width="1"/>
<text x="278" y="106" text-anchor="middle" font-size="9.5" fill="currentColor" opacity="0.6">empty: pure cost</text>
<text x="458" y="44" text-anchor="middle" font-size="10" fill="currentColor" opacity="0.8">shard 2</text>
<rect x="386" y="52" width="144" height="40" fill="none" stroke="currentColor" stroke-width="1.5"/>
<rect x="394" y="60" width="30" height="24" fill="var(--color-accent, #b2570a)" fill-opacity="0.45" stroke="currentColor" stroke-width="1"/>
<rect x="428" y="60" width="30" height="24" fill="var(--color-accent, #b2570a)" fill-opacity="0.45" stroke="currentColor" stroke-width="1"/>
<rect x="462" y="60" width="30" height="24" fill="var(--color-accent, #b2570a)" fill-opacity="0.45" stroke="currentColor" stroke-width="1"/>
<rect x="496" y="60" width="26" height="24" fill="var(--color-accent, #b2570a)" fill-opacity="0.45" stroke="currentColor" stroke-width="1"/>
<text x="458" y="106" text-anchor="middle" font-size="9.5" fill="#d1495b">full: back-pressures P3 alone</text>
<text x="638" y="44" text-anchor="middle" font-size="10" fill="currentColor" opacity="0.8">shard 3</text>
<rect x="566" y="52" width="144" height="40" fill="none" stroke="currentColor" stroke-width="1.5"/>
<rect x="574" y="60" width="30" height="24" fill="var(--color-accent, #b2570a)" fill-opacity="0.45" stroke="currentColor" stroke-width="1"/>
<rect x="608" y="60" width="30" height="24" fill="var(--color-surface, #e7e3d7)" stroke="currentColor" stroke-width="1"/>
<rect x="642" y="60" width="30" height="24" fill="var(--color-surface, #e7e3d7)" stroke="currentColor" stroke-width="1"/>
<rect x="676" y="60" width="26" height="24" fill="var(--color-surface, #e7e3d7)" stroke="currentColor" stroke-width="1"/>
<path d="M170 132 L206 132" stroke="currentColor" stroke-width="1.2" marker-end="url(#fw-sd-ah)" opacity="0.7"/>
<path d="M350 132 L386 132" stroke="currentColor" stroke-width="1.2" marker-end="url(#fw-sd-ah)" opacity="0.7"/>
<path d="M530 132 L566 132" stroke="currentColor" stroke-width="1.2" marker-end="url(#fw-sd-ah)" opacity="0.7"/>
<path d="M710 132 C 740 132 744 154 716 158 L 60 158 C 30 158 26 140 26 132" fill="none" stroke="currentColor" stroke-width="1.2" stroke-dasharray="4 4" marker-end="url(#fw-sd-ah)" opacity="0.55"/>
<text x="98" y="132" text-anchor="middle" font-size="10" fill="currentColor" opacity="0.7">walk</text>
<text x="278" y="132" text-anchor="middle" font-size="10" fill="currentColor" opacity="0.7">walk</text>
<text x="458" y="132" text-anchor="middle" font-size="10" fill="currentColor" opacity="0.7">walk</text>
<text x="638" y="132" text-anchor="middle" font-size="10" fill="currentColor" opacity="0.7">walk</text>
<line x1="98" y1="94" x2="330" y2="188" stroke="currentColor" stroke-width="1" opacity="0.45"/>
<line x1="278" y1="94" x2="360" y2="188" stroke="currentColor" stroke-width="1" opacity="0.45"/>
<line x1="458" y1="94" x2="400" y2="188" stroke="currentColor" stroke-width="1" opacity="0.45"/>
<line x1="638" y1="94" x2="430" y2="188" stroke="currentColor" stroke-width="1" opacity="0.45"/>
<rect x="305" y="190" width="150" height="34" fill="var(--color-accent, #b2570a)" fill-opacity="0.25" stroke="currentColor" stroke-width="1.5"/>
<text x="380" y="212" text-anchor="middle" font-size="12" fill="currentColor">one consumer</text>
<text x="380" y="252" text-anchor="middle" font-size="11" fill="currentColor">Arm every shard, wake on a publish from any of them, then walk them all again.</text>
<text x="380" y="270" text-anchor="middle" font-size="11" fill="currentColor" opacity="0.85">Arming is O(N), so at 64 shards and 4 producers the walk over empty rings costs more than the contention it saves.</text>
</svg>
<figcaption>The rotating start is what stops a busy shard starving the others: the walk does not begin at shard 0 every pass. The trade is visible in the middle of the diagram. Every empty ring the consumer visits is work that a single ring would never have done, which is why shard count is not free to raise and why the sweep below turns against 64 shards exactly where producers are scarce.</figcaption>
</figure>

Five hundred thousand messages, one consumer, 65,536 slots total in every configuration so the comparison is at equal memory. Kmsg/s:

| senders | 1 ring | 4 shards | 16 shards | 64 shards |
|--------:|-------:|---------:|----------:|----------:|
| 1 | 5,918 | 6,565 | **6,988** | 6,866 |
| 2 | 10,414 | 13,623 | **14,276** | 13,777 |
| 4 | 16,590 | **20,033** | 18,921 | 10,485 |
| 8 | 11,774 | 20,871 | **21,104** | 10,272 |
| 16 | 11,851 | 18,808 | **20,434** | 14,228 |
| 32 | 11,181 | 18,467 | **18,714** | 17,035 |
| 64 | 11,436 | **18,729** | 18,219 | 16,919 |
| 100 | 10,940 | **18,748** | 17,945 | 17,016 |
| 250 | 10,055 | **16,983** | 16,086 | 16,028 |
| 1000 | 9,028 | 10,715 | **12,502** | 11,861 |

Four shards beat or match a single ring at every sender count measured, by 1.2 to 1.8×. The interesting band is eight to 250 senders, where the single ring has already collapsed to around 11,000 and four shards hold near 19,000. At one thousand producers both fall away and the margin narrows to 1.2×.

Sixty-four shards are the cautionary column. At four and eight senders they run at roughly half the four-shard number, because the consumer is spending its round walking rings that have nothing in them. More shards only help once producers genuinely outnumber them. Four is the default I would reach for.

### what you give up

**Global ordering.** A single ring totally orders every item from every producer. Shards preserve order per producer and nothing more. If you need a global sequence, this is the wrong module.

**Fungible capacity.** Capacity is `shards × capacity_each`, but a producer can only draw on its own shard's share. One hot producer gets back-pressure while the other shards sit empty, where a single ring would have pooled the space.

## where it sits against what you would reach for instead

The contention story is one operation in ERTS. With the default `message_queue_data: :on_heap`, every `send/2` attempts a trylock on one word of the receiver's process struct, and it collapses as senders climb:

| senders | `on_heap` | `off_heap` | flywheel |
|--------:|----------:|-----------:|---------:|
| 1 | 10,181 | 9,182 | 5,204 |
| 4 | 4,376 | 9,119 | **17,432** |
| 8 | **1,142** | 17,796 | 12,323 |
| 100 | 494 | 12,737 | 9,266 |
| 1000 | 281 | 13,204 | 8,074 |

Kmsg/s. Note the third column at one sender: flywheel is roughly half the mailbox's speed there, and that is the honest shape of the thing. This is not a faster queue, it is a bounded one, and at low fan-in you are paying for a property you are not using.

The part I want to be loud about is the `off_heap` flag. It fixes the cliff, and in that isolated, drain-bound probe one process flag beats flywheel by about 1.4 to 1.9× from eight senders up. If raw drain-bound throughput is all you need, `Process.flag(:message_queue_data, :off_heap)` is one line and you can stop reading. What the flag does not give you is a bound, which is why the end-to-end flood table at the top of this post looks different from this one: there, the ring is 1.55 to 1.57× ahead *while* holding a thirtieth of the memory, because bounded occupancy is itself a throughput mechanism once a system saturates.

Against the rest of the usual toolbox under the same 100-producer flood. This is explicitly not like-for-like; it measures each tool's overload posture:

| transport | Kmsg/s | peak memory | p50 | posture |
|---|---:|---:|---:|---|
| flywheel (back-pressure) | **6,738** | **2.1 MB** | **544 µs** | pushes back |
| flywheel (drop-on-full) | 2,316 | 0.8 MB | 590 µs | delivered 19%, the price of dropping |
| mailbox `off_heap` | 4,504 | 52.5 MB | 44.2 ms | absorbs into memory |
| GenStage | 262 | 91.5 MB | 822 ms | demand does not reach raw senders |
| `:queue` in a GenServer | 234 | 94.6 MB | 1.64 s | serialises on one process |
| mailbox (default) | 224 | 56.7 MB | 1.67 s | the cliff, above |
| ETS `ordered_set` | 61 | 33.2 MB | 3.75 s | readers poll |

The drop-on-full row is the one I would not want quoted without its fourth column. Under a 50× overload it delivered 19% of what was offered. That is the policy working exactly as specified, and it is also why it is not the default.

## the worked example: a CME-style feed

Synthetic floods cannot tell you what boundedness is *worth*, because a synthetic payload costs nothing by arriving late. Market data does. A price from 40 ms ago is not a price, it is history, and a strategy acting on it is betting money on a number already known to be wrong.

So the worked example is a futures feed handler: four decoders publishing CME-shaped book updates into one book builder, across five instruments: E-mini S&P 500, E-mini Nasdaq-100, WTI Crude, COMEX Gold, and the 10-year T-note with its 1/64 tick.

### the payload

Each update packs into a single integer. Not 63 bits, which is what `:atomics` would let you use, but **59**:

<!-- fig:pack -->
<figure class="diagram">
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 760 200" role="img" aria-label="A book update packed into 59 bits: 11 bits instrument, 21 bits price ticks, 14 bits size, 4 bits level, 2 bits side, 2 bits action, 5 low bits of packet sequence" style="width:100%;height:auto;max-width:760px;font-family:ui-monospace,Menlo,Consolas,monospace;font-size:13px;color:var(--color-fg,currentColor)">
<text x="119" y="58" text-anchor="middle" font-size="10" fill="currentColor" opacity="0.75">58..48</text>
<text x="293" y="58" text-anchor="middle" font-size="10" fill="currentColor" opacity="0.75">47..27</text>
<text x="483" y="58" text-anchor="middle" font-size="10" fill="currentColor" opacity="0.75">26..13</text>
<text x="580" y="58" text-anchor="middle" font-size="9" fill="currentColor" opacity="0.75">12..9</text>
<text x="613" y="58" text-anchor="middle" font-size="9" fill="currentColor" opacity="0.75">8..7</text>
<text x="635" y="58" text-anchor="middle" font-size="9" fill="currentColor" opacity="0.75">6..5</text>
<text x="673" y="58" text-anchor="middle" font-size="9" fill="currentColor" opacity="0.75">4..0</text>
<rect x="60" y="68" width="119" height="40" fill="#2e86ab" fill-opacity="0.4" stroke="currentColor" stroke-width="1"/>
<rect x="179" y="68" width="228" height="40" fill="var(--color-accent, #b2570a)" fill-opacity="0.45" stroke="currentColor" stroke-width="1"/>
<rect x="407" y="68" width="152" height="40" fill="#3a9d5d" fill-opacity="0.4" stroke="currentColor" stroke-width="1"/>
<rect x="559" y="68" width="43" height="40" fill="#9b5de5" fill-opacity="0.4" stroke="currentColor" stroke-width="1"/>
<rect x="602" y="68" width="22" height="40" fill="#d1495b" fill-opacity="0.4" stroke="currentColor" stroke-width="1"/>
<rect x="624" y="68" width="22" height="40" fill="#2e86ab" fill-opacity="0.4" stroke="currentColor" stroke-width="1"/>
<rect x="646" y="68" width="54" height="40" fill="var(--color-border, #cfcabb)" fill-opacity="0.9" stroke="currentColor" stroke-width="1"/>
<text x="119" y="93" text-anchor="middle" font-size="12" fill="currentColor">instrument</text>
<text x="293" y="93" text-anchor="middle" font-size="12" fill="currentColor">price ticks</text>
<text x="483" y="93" text-anchor="middle" font-size="12" fill="currentColor">size</text>
<text x="52" y="93" text-anchor="end" font-size="10" fill="currentColor" opacity="0.75">bit 58</text>
<text x="708" y="93" text-anchor="start" font-size="10" fill="currentColor" opacity="0.75">bit 0</text>
<line x1="580" y1="110" x2="548" y2="136" stroke="currentColor" stroke-width="1" opacity="0.6"/>
<line x1="613" y1="110" x2="600" y2="136" stroke="currentColor" stroke-width="1" opacity="0.6"/>
<line x1="635" y1="110" x2="650" y2="136" stroke="currentColor" stroke-width="1" opacity="0.6"/>
<line x1="673" y1="110" x2="706" y2="136" stroke="currentColor" stroke-width="1" opacity="0.6"/>
<text x="548" y="149" text-anchor="middle" font-size="10" fill="currentColor">level</text>
<text x="600" y="149" text-anchor="middle" font-size="10" fill="currentColor">side</text>
<text x="650" y="149" text-anchor="middle" font-size="10" fill="currentColor">action</text>
<text x="706" y="149" text-anchor="middle" font-size="10" fill="currentColor">seq_lo</text>
<text x="380" y="180" text-anchor="middle" font-size="11" fill="currentColor" opacity="0.85">2^59 − 1 = 576,460,752,303,423,487, the largest immediate integer on 64-bit BEAM.</text>
<text x="380" y="194" text-anchor="middle" font-size="11" fill="currentColor" opacity="0.85">One bit more and every payload is a two-word bignum on the heap.</text>
</svg>
<figcaption>The layout is cut to fit under the BEAM's immediate-integer boundary. A 63-bit packing would put an allocation on both sides of a transport chosen specifically to avoid allocations, once in the producer building the value, once in the consumer receiving it.</figcaption>
</figure>

```elixir
# 11 bits instrument | 21 price ticks | 14 size | 4 level | 2 side | 2 action | 5 seq
def pack(inst, ticks, size, level, side, action, seq)
    when inst in 0..2047 and ticks in 0..2_097_151 and size in 0..16_383 and
         level in 0..10 and side in 0..3 and action in 0..3 do
  inst <<< 48 ||| ticks <<< 27 ||| size <<< 13 ||| level <<< 9 |||
    side <<< 7 ||| action <<< 5 ||| (seq &&& 0x1F)
end
```

Two details in there that I like more than the bit-fiddling. Prices are tick indices rather than decimals, which is what makes 21 bits enough for every listed contract and what makes the arithmetic exact: the decoder asserts `rem(micros, tick) == 0`, so a price that is not a whole number of ticks is a decode bug rather than something to round away. And nothing is clamped: every field is guarded, so a contract the venue relists outside 21 bits of ticks raises a `FunctionClauseError` in the decoder rather than silently becoming a different price inside the book.

The five `seq_lo` bits are the cheapest thing in the layout and do the most interesting job.

### capacity is denominated in time

The consumer folds updates straight into an `:atomics` book, mutated in place, invisible to every collector. Sweeping ring capacity over 500k updates, unthrottled, median of nine rounds:

| transport | Kmsg/s | drain (ns/item) | peak outstanding | book lag | staleness bound |
|---|---:|---:|---:|---:|---:|
| `off_heap` mailbox | 13,597 | 73.5 | 101,617 | 7,469 µs | **none** |
| flywheel 32768 | 14,429 | 69.0 | 32,768 | 2,261 µs | **2,261 µs** |
| flywheel 16384 | 11,699 | 68.5 | 14,966 | 1,025 µs | 1,122 µs |
| flywheel 8192 | 7,314 | 72.1 | 8,192 | 591 µs | 591 µs |
| flywheel 1024 | 1,535 | 90.7 | 1,024 | 93 µs | 93 µs |

The column that earns the library is the last one, and it comes out of a single multiplication.

<!-- fig:capacity -->
<figure class="diagram">
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 760 300" role="img" aria-label="Three ring buffers of decreasing capacity, each annotated with capacity times drain cost giving a staleness ceiling, beside an open-ended mailbox queue that runs off the edge of the frame with no ceiling" style="width:100%;height:auto;max-width:760px;font-family:ui-monospace,Menlo,Consolas,monospace;font-size:13px;color:var(--color-fg,currentColor)">
<defs><marker id="fw-cap-ah" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0L10 5L0 10z" fill="currentColor"/></marker></defs>
<text x="245" y="24" text-anchor="middle" font-size="12" fill="currentColor" font-weight="bold">capacity × drain cost = a ceiling the market cannot exceed</text>
<circle cx="110" cy="150" r="72" fill="var(--color-accent, #b2570a)" fill-opacity="0.35" stroke="currentColor" stroke-width="1"/>
<circle cx="110" cy="150" r="52" fill="var(--color-bg, #f2efe6)" stroke="currentColor" stroke-width="1"/>
<circle cx="290" cy="150" r="48" fill="var(--color-accent, #b2570a)" fill-opacity="0.35" stroke="currentColor" stroke-width="1"/>
<circle cx="290" cy="150" r="33" fill="var(--color-bg, #f2efe6)" stroke="currentColor" stroke-width="1"/>
<circle cx="420" cy="150" r="28" fill="var(--color-accent, #b2570a)" fill-opacity="0.35" stroke="currentColor" stroke-width="1"/>
<circle cx="420" cy="150" r="18" fill="var(--color-bg, #f2efe6)" stroke="currentColor" stroke-width="1"/>
<text x="110" y="245" text-anchor="middle" font-size="11" fill="currentColor" font-weight="bold">32,768 slots</text>
<text x="110" y="261" text-anchor="middle" font-size="10" fill="currentColor" opacity="0.8">× 69.0 ns drain</text>
<text x="110" y="278" text-anchor="middle" font-size="11" fill="currentColor" font-weight="bold">= 2,261 µs</text>
<text x="290" y="245" text-anchor="middle" font-size="11" fill="currentColor" font-weight="bold">8,192 slots</text>
<text x="290" y="261" text-anchor="middle" font-size="10" fill="currentColor" opacity="0.8">× 72.1 ns</text>
<text x="290" y="278" text-anchor="middle" font-size="11" fill="currentColor" font-weight="bold">= 591 µs</text>
<text x="420" y="245" text-anchor="middle" font-size="11" fill="currentColor" font-weight="bold">1,024 slots</text>
<text x="420" y="261" text-anchor="middle" font-size="10" fill="currentColor" opacity="0.8">× 90.7 ns</text>
<text x="420" y="278" text-anchor="middle" font-size="11" fill="currentColor" font-weight="bold">= 93 µs</text>
<line x1="492" y1="45" x2="492" y2="290" stroke="currentColor" stroke-width="1" stroke-dasharray="4 4" opacity="0.45"/>
<text x="630" y="110" text-anchor="middle" font-size="10" fill="currentColor" opacity="0.8">grows until memory runs out</text>
<rect x="515" y="136" width="24" height="28" fill="#d1495b" fill-opacity="0.45" stroke="currentColor" stroke-width="1"/>
<rect x="542" y="136" width="24" height="28" fill="#d1495b" fill-opacity="0.45" stroke="currentColor" stroke-width="1"/>
<rect x="569" y="136" width="24" height="28" fill="#d1495b" fill-opacity="0.4" stroke="currentColor" stroke-width="1"/>
<rect x="596" y="136" width="24" height="28" fill="#d1495b" fill-opacity="0.34" stroke="currentColor" stroke-width="1"/>
<rect x="623" y="136" width="24" height="28" fill="#d1495b" fill-opacity="0.26" stroke="currentColor" stroke-width="1"/>
<rect x="650" y="136" width="24" height="28" fill="#d1495b" fill-opacity="0.18" stroke="currentColor" stroke-width="1"/>
<rect x="677" y="136" width="24" height="28" fill="#d1495b" fill-opacity="0.1" stroke="currentColor" stroke-width="1"/>
<line x1="708" y1="150" x2="752" y2="150" stroke="currentColor" stroke-width="1.5" stroke-dasharray="4 3" marker-end="url(#fw-cap-ah)"/>
<text x="630" y="245" text-anchor="middle" font-size="11" fill="currentColor" font-weight="bold">off_heap mailbox</text>
<text x="630" y="261" text-anchor="middle" font-size="10" fill="currentColor" opacity="0.8">peaked at 101,617 items</text>
<text x="630" y="278" text-anchor="middle" font-size="11" fill="currentColor" font-weight="bold">= 7,469 µs, no ceiling</text>
</svg>
<figcaption>The rings are schematic, not to scale. The point is the arithmetic under each: a ring's capacity, multiplied by what one update costs to apply, is a hard upper bound on how stale the top of book can be when a strategy reads it at the worst moment of a burst. The mailbox's 7,469 µs is simply what it happened to reach in these nine rounds. It is not a limit of any kind.</figcaption>
</figure>

Look at the `drain ns` column in the table above: it stays between 69 and 91 ns across an eightfold capacity sweep. That flatness is the control. It says the metric is measuring the cost of *applying* an update rather than the cost of waiting around for one, which is what makes the arms comparable at all. The drift to ~90 ns at the bottom of the sweep is per-batch fixed cost amortised over smaller batches, not a slower drain.

And notice that at 32,768 and below, peak outstanding equals capacity *exactly*. The ring did not approach its ceiling, it sat on it, which is the clearest demonstration of what the bound column means.

Two caveats about that sweep, because it is easy to read the wrong lesson off it. The throughput knee at 8,192 is real but it is an artefact of the probe: this thing offers about 14M updates/s, far beyond any real channel. At a sustainable feed rate the small ring never fills at all, and its 93 µs bound is free. And the 32,768-slot row beating the mailbox on throughput, 14,429 against 13,597, is well inside run-to-run spread. I would call that a tie and take the 2.3 ms ceiling as the entire prize.

### two policies, one library

The example is also why one library ships both push functions.

The **feed** side takes `push/2` and never blocks. The exchange will not slow down for you, and a late quote is worthless anyway. What makes the refusal safe is those five `seq_lo` bits: offer sequences 0..79 into a 64-slot ring and you get 64 accepted, 16 refused, and a consumer whose sequence check reports a gap of exactly 16. That is a *counted, recoverable* gap you take to the venue's recovery channel, rather than silently growing staleness.

The **order and fill** side takes `push_wait/3`. Losing a fill is not an option, and neither is a risk process minutes behind the exchange. On a full 8-slot ring:

```text
push_wait(.., 100ms) -> {:error, :timeout} after 99125 us
full? true, still 8 items, nothing lost
```

That return value is the entire point. `send/2` has no way to say it, so the backlog goes somewhere you cannot see until the node dies. Here it is a value you can alert on, throttle on, or trip a circuit breaker with.

## about these numbers

Everything here was measured on one host: an i5-13600K on OTP 29, in a container with pinned cores, because the Windows host clamps the monotonic clock to about 102 µs and that is larger than several of the things being measured. It is not an environment that shows what the design can really do, and the absolute figures should not travel. The relative shape held across runs well enough that it seemed worth sharing early.

## status

I will likely open source it once I have built some confidence in it and jumped through the appropriate hoops to do so. I am still tinkering, and I will write more on the topic when I have more to share, mpmc next up and experiments in pointing to off heap refc binaries for richer data types and comparing the throughput in combination.  From this some form of an SBE port and the list goes on...

What exists: 72 correctness tests covering exactly-once delivery under back-pressure, per-producer ordering, the 2^59 sequence wrap including batches that straddle it, producer death mid-claim, the park/wake race, sharded rings, and both channel handler modes. What does not exist: a stable API, a released package, or any production mileage whatsoever.

If you are hitting the failure mode at the top of this post today, the answer is almost certainly `Process.flag(:message_queue_data, :off_heap)`, or NIFs to add some cool data structures, or scaling horizontally using GenStage or one of the many other options.  In the meantime I am going to continue pretending I have proper arrays on my favorite platform to see what good stuff will fall out as I extend the capability set.
