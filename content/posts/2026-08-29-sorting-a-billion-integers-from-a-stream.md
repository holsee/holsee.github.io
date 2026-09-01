---
title: "Sorting a billion integers from a stream"
description: "A follow-up to the sixteen-core post at the scale where it matters: a billion keys arriving over the network, what a radix sort can do while they arrive, what it must leave until the last byte, and what an analytics node actually does with this every hour."
tags: [personal, algorithms, dotnet, elixir, distributed-systems]
---

## the short version

At a billion keys, radix sort is the only sort that keeps up with the network. A billion 32-bit integers is 4 GB. Over 10 GbE that takes about three seconds to arrive; `Array.Sort` then needs 66 s to sort them on one thread, and the sixteen-thread radix sort from the [previous post](/radix-sort-on-sixteen-cores/) needs 0.7. Once the sort is faster than the ingest, the design question changes: it's no longer how fast you can sort, it's how much of the sort you can do while the data is still arriving. The answer is about a third of it. Partition each chunk by its top bits the moment it lands, count as you go, and after the last byte only the two private scatters remain: half a second to a fully sorted billion, down from 0.9.

The shape is the one production engines use. An analytics node ingesting a billion rows an hour doesn't sort a billion rows; it sorts each arriving block as it lands, writes it as a sorted run, and merges runs in the background. Radix sort is the tool inside that shape for numeric keys, and this post is the inside of one such block, at a size where the constants are the whole story.

## the case: a billion rows an hour, one node

In 2018 Cloudflare wrote up their HTTP analytics pipeline: 6M requests a second at the edge, 11M rows a second into a 36-node ClickHouse cluster, 47 Gbps of inserts, Kafka in between with 106 partitions and a Go consumer per partition batching rows into inserts. Per node that's about 300,000 rows a second, a billion rows every hour, arriving from a dozen or so streams. That's the shape and the scale of this post, and it hasn't got smaller since.

What the node does with each insert is the interesting part. A MergeTree table writes every insert as a separate part, and "each of them is lexicographically sorted by primary key"; a background process then merges parts together. The sort on insert is where the row order comes from, the merge keeps the number of parts bounded, and for numeric key columns the sort ClickHouse reaches for is its own radix sort (LSD, stable, in `RadixSort.h`). So the unit of work is: rows arrive from N streams, a block of them is sorted by key, the sorted block is written. That is exactly what follows, with the block scaled up to a billion 32-bit account ids so that the constants have nowhere to hide. Real rows carry a hundred other columns; those move by the sorted permutation afterwards, and the key sort is still the part that decides whether the node keeps up.

## what can happen while the data arrives

The previous post ended with the fastest in-memory version: one MSD pass partitions the input into 1,024 buckets by the top 10 bits, then each bucket is sorted privately on its low 22 bits with two 11-bit passes. Look at that from the point of view of a chunk landing off the network.

The MSD partition doesn't need anything global. A key's bucket is its top 10 bits, and if every stream keeps its own 1,024 buckets as growable lists of pages, a key can go into its page the moment it arrives. No prefix sum, no knowledge of n, nothing shared between streams. The histograms of the low digits don't need anything global either: two increments per key into the arriving bucket's counters.

What can't happen on arrival is the scatter. A stable scatter into a bucket's final range needs the bucket's complete histogram, and that isn't known until the last key has landed. So the two private passes are the floor: after the last byte you owe two sweeps over the data, and nothing else.

<!-- fig:pages -->
<figure class="diagram">
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 760 300" role="img" aria-label="Per-stream pages while data arrives, then one bucket gathered from every stream and sorted privately" style="width:100%;height:auto;max-width:760px;font-family:ui-monospace,Menlo,Consolas,monospace;font-size:13px;color:var(--color-fg,currentColor)">
<defs><marker id="ah" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0L10 5L0 10z" fill="currentColor"/></marker></defs>
<text x="60" y="24" text-anchor="start" font-size="13" fill="currentColor" font-weight="bold">while data arrives</text>
<text x="94" y="42" text-anchor="middle" font-size="12" fill="currentColor" >b0</text>
<text x="156" y="42" text-anchor="middle" font-size="12" fill="currentColor" >b1</text>
<text x="218" y="42" text-anchor="middle" font-size="12" fill="currentColor" >…</text>
<text x="280" y="42" text-anchor="middle" font-size="12" fill="currentColor" >b1022</text>
<text x="342" y="42" text-anchor="middle" font-size="12" fill="currentColor" >b1023</text>
<text x="58" y="74" text-anchor="end" font-size="12" fill="currentColor" >s0</text>
<rect x="74" y="62" width="40" height="14" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="78" y="55" width="40" height="14" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="136" y="62" width="40" height="14" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="140" y="55" width="40" height="14" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<text x="218" y="74" text-anchor="middle" font-size="12" fill="currentColor" >…</text>
<rect x="260" y="62" width="40" height="14" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="264" y="55" width="40" height="14" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="268" y="48" width="40" height="14" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="322" y="62" width="40" height="14" fill="#2e86ab" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="58" y="114" text-anchor="end" font-size="12" fill="currentColor" >s1</text>
<rect x="74" y="102" width="40" height="14" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="136" y="102" width="40" height="14" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<text x="218" y="114" text-anchor="middle" font-size="12" fill="currentColor" >…</text>
<rect x="260" y="102" width="40" height="14" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="264" y="95" width="40" height="14" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="322" y="102" width="40" height="14" fill="#2e86ab" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="58" y="154" text-anchor="end" font-size="12" fill="currentColor" >s2</text>
<rect x="74" y="142" width="40" height="14" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="78" y="135" width="40" height="14" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="136" y="142" width="40" height="14" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<text x="218" y="154" text-anchor="middle" font-size="12" fill="currentColor" >…</text>
<rect x="260" y="142" width="40" height="14" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="322" y="142" width="40" height="14" fill="#2e86ab" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<rect x="326" y="135" width="40" height="14" fill="#2e86ab" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<rect x="330" y="128" width="40" height="14" fill="#2e86ab" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="58" y="194" text-anchor="end" font-size="12" fill="currentColor" >…</text>
<text x="94" y="194" text-anchor="middle" font-size="12" fill="currentColor" >…</text>
<text x="156" y="194" text-anchor="middle" font-size="12" fill="currentColor" >…</text>
<text x="218" y="194" text-anchor="middle" font-size="12" fill="currentColor" >…</text>
<text x="280" y="194" text-anchor="middle" font-size="12" fill="currentColor" >…</text>
<text x="342" y="194" text-anchor="middle" font-size="12" fill="currentColor" >…</text>
<text x="58" y="234" text-anchor="end" font-size="12" fill="currentColor" >s15</text>
<rect x="74" y="222" width="40" height="14" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="78" y="215" width="40" height="14" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="82" y="208" width="40" height="14" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="136" y="222" width="40" height="14" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<text x="218" y="234" text-anchor="middle" font-size="12" fill="currentColor" >…</text>
<rect x="260" y="222" width="40" height="14" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="264" y="215" width="40" height="14" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="322" y="222" width="40" height="14" fill="#2e86ab" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<rect x="316" y="28" width="62" height="208" fill="none" stroke="currentColor" stroke-dasharray="4 3"/>
<text x="470" y="24" text-anchor="start" font-size="13" fill="currentColor" font-weight="bold">after the last byte, per bucket</text>
<line x1="382" y1="140" x2="462" y2="140" stroke="currentColor" stroke-width="1" marker-end="url(#ah)" />
<rect x="470" y="50" width="270" height="52" fill="#2e86ab" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="605" y="72" text-anchor="middle" font-size="12" fill="currentColor" >bucket 1023's pages, every stream,</text>
<text x="605" y="90" text-anchor="middle" font-size="12" fill="currentColor" >in arrival order</text>
<line x1="605" y1="104" x2="605" y2="128" stroke="currentColor" stroke-width="1" marker-end="url(#ah)" />
<rect x="470" y="130" width="270" height="52" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<text x="605" y="152" text-anchor="middle" font-size="12" fill="currentColor" >scratch: pass A</text>
<text x="605" y="170" text-anchor="middle" font-size="12" fill="currentColor" >on the low digit</text>
<line x1="605" y1="184" x2="605" y2="208" stroke="currentColor" stroke-width="1" marker-end="url(#ah)" />
<rect x="470" y="210" width="270" height="52" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<text x="605" y="232" text-anchor="middle" font-size="12" fill="currentColor" >final range: pass B</text>
<text x="605" y="250" text-anchor="middle" font-size="12" fill="currentColor" >on the middle digit</text>
</svg>
<figcaption>Each stream appends to its own pages, one stack per bucket, while data arrives. After the last byte a bucket's pages from every stream are read straight into two private passes.</figcaption>
</figure>
<!-- /fig:pages -->

Here's the partitioner, one per input stream, called on the stream's own thread with each chunk. Three things happen per key: it's appended to its bucket's open page, the bucket's count goes up, and its two lower digits are counted for the passes that come later.

<!-- fig:digits -->
<figure class="diagram">
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 760 135" role="img" aria-label="A 32-bit key as three digits: top 10 bits pick the bucket on arrival, then two private 11-bit passes" style="width:100%;height:auto;max-width:760px;font-family:ui-monospace,Menlo,Consolas,monospace;font-size:13px;color:var(--color-fg,currentColor)">
<defs><marker id="ah" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0L10 5L0 10z" fill="currentColor"/></marker></defs>
<rect x="60" y="34" width="20" height="26" fill="var(--color-accent, #b2570a)" fill-opacity="0.35" stroke="currentColor" stroke-width="1" />
<rect x="80" y="34" width="20" height="26" fill="var(--color-accent, #b2570a)" fill-opacity="0.35" stroke="currentColor" stroke-width="1" />
<rect x="100" y="34" width="20" height="26" fill="var(--color-accent, #b2570a)" fill-opacity="0.35" stroke="currentColor" stroke-width="1" />
<rect x="120" y="34" width="20" height="26" fill="var(--color-accent, #b2570a)" fill-opacity="0.35" stroke="currentColor" stroke-width="1" />
<rect x="140" y="34" width="20" height="26" fill="var(--color-accent, #b2570a)" fill-opacity="0.35" stroke="currentColor" stroke-width="1" />
<rect x="160" y="34" width="20" height="26" fill="var(--color-accent, #b2570a)" fill-opacity="0.35" stroke="currentColor" stroke-width="1" />
<rect x="180" y="34" width="20" height="26" fill="var(--color-accent, #b2570a)" fill-opacity="0.35" stroke="currentColor" stroke-width="1" />
<rect x="200" y="34" width="20" height="26" fill="var(--color-accent, #b2570a)" fill-opacity="0.35" stroke="currentColor" stroke-width="1" />
<rect x="220" y="34" width="20" height="26" fill="var(--color-accent, #b2570a)" fill-opacity="0.35" stroke="currentColor" stroke-width="1" />
<rect x="240" y="34" width="20" height="26" fill="var(--color-accent, #b2570a)" fill-opacity="0.35" stroke="currentColor" stroke-width="1" />
<rect x="260" y="34" width="20" height="26" fill="var(--color-border, #cfcabb)" fill-opacity="0.9" stroke="currentColor" stroke-width="1" />
<rect x="280" y="34" width="20" height="26" fill="var(--color-border, #cfcabb)" fill-opacity="0.9" stroke="currentColor" stroke-width="1" />
<rect x="300" y="34" width="20" height="26" fill="var(--color-border, #cfcabb)" fill-opacity="0.9" stroke="currentColor" stroke-width="1" />
<rect x="320" y="34" width="20" height="26" fill="var(--color-border, #cfcabb)" fill-opacity="0.9" stroke="currentColor" stroke-width="1" />
<rect x="340" y="34" width="20" height="26" fill="var(--color-border, #cfcabb)" fill-opacity="0.9" stroke="currentColor" stroke-width="1" />
<rect x="360" y="34" width="20" height="26" fill="var(--color-border, #cfcabb)" fill-opacity="0.9" stroke="currentColor" stroke-width="1" />
<rect x="380" y="34" width="20" height="26" fill="var(--color-border, #cfcabb)" fill-opacity="0.9" stroke="currentColor" stroke-width="1" />
<rect x="400" y="34" width="20" height="26" fill="var(--color-border, #cfcabb)" fill-opacity="0.9" stroke="currentColor" stroke-width="1" />
<rect x="420" y="34" width="20" height="26" fill="var(--color-border, #cfcabb)" fill-opacity="0.9" stroke="currentColor" stroke-width="1" />
<rect x="440" y="34" width="20" height="26" fill="var(--color-border, #cfcabb)" fill-opacity="0.9" stroke="currentColor" stroke-width="1" />
<rect x="460" y="34" width="20" height="26" fill="var(--color-border, #cfcabb)" fill-opacity="0.9" stroke="currentColor" stroke-width="1" />
<rect x="480" y="34" width="20" height="26" fill="var(--color-surface, #e7e3d7)" fill-opacity="0.9" stroke="currentColor" stroke-width="1" />
<rect x="500" y="34" width="20" height="26" fill="var(--color-surface, #e7e3d7)" fill-opacity="0.9" stroke="currentColor" stroke-width="1" />
<rect x="520" y="34" width="20" height="26" fill="var(--color-surface, #e7e3d7)" fill-opacity="0.9" stroke="currentColor" stroke-width="1" />
<rect x="540" y="34" width="20" height="26" fill="var(--color-surface, #e7e3d7)" fill-opacity="0.9" stroke="currentColor" stroke-width="1" />
<rect x="560" y="34" width="20" height="26" fill="var(--color-surface, #e7e3d7)" fill-opacity="0.9" stroke="currentColor" stroke-width="1" />
<rect x="580" y="34" width="20" height="26" fill="var(--color-surface, #e7e3d7)" fill-opacity="0.9" stroke="currentColor" stroke-width="1" />
<rect x="600" y="34" width="20" height="26" fill="var(--color-surface, #e7e3d7)" fill-opacity="0.9" stroke="currentColor" stroke-width="1" />
<rect x="620" y="34" width="20" height="26" fill="var(--color-surface, #e7e3d7)" fill-opacity="0.9" stroke="currentColor" stroke-width="1" />
<rect x="640" y="34" width="20" height="26" fill="var(--color-surface, #e7e3d7)" fill-opacity="0.9" stroke="currentColor" stroke-width="1" />
<rect x="660" y="34" width="20" height="26" fill="var(--color-surface, #e7e3d7)" fill-opacity="0.9" stroke="currentColor" stroke-width="1" />
<rect x="680" y="34" width="20" height="26" fill="var(--color-surface, #e7e3d7)" fill-opacity="0.9" stroke="currentColor" stroke-width="1" />
<text x="70.0" y="26" text-anchor="middle" font-size="11" fill="currentColor" >31</text>
<text x="250.0" y="26" text-anchor="middle" font-size="11" fill="currentColor" >22</text>
<text x="270.0" y="26" text-anchor="middle" font-size="11" fill="currentColor" >21</text>
<text x="470.0" y="26" text-anchor="middle" font-size="11" fill="currentColor" >11</text>
<text x="490.0" y="26" text-anchor="middle" font-size="11" fill="currentColor" >10</text>
<text x="690.0" y="26" text-anchor="middle" font-size="11" fill="currentColor" >0</text>
<text x="52" y="52" text-anchor="end" font-size="11" fill="currentColor" >bit</text>
<path d="M60 66 v6 H260 v-6" fill="none" stroke="currentColor" stroke-width="1"/>
<text x="160.0" y="86" text-anchor="middle" font-size="12" fill="currentColor" >top 10 bits: the bucket</text>
<path d="M260 66 v6 H480 v-6" fill="none" stroke="currentColor" stroke-width="1"/>
<text x="370.0" y="86" text-anchor="middle" font-size="12" fill="currentColor" >middle 11 bits: pass B</text>
<path d="M480 66 v6 H700 v-6" fill="none" stroke="currentColor" stroke-width="1"/>
<text x="590.0" y="86" text-anchor="middle" font-size="12" fill="currentColor" >low 11 bits: pass A</text>
<text x="60" y="116" text-anchor="start" font-size="12" fill="currentColor" >key >> 22</text>
<text x="370" y="116" text-anchor="middle" font-size="12" fill="currentColor" >(key >> 11) &amp; 0x7FF</text>
<text x="590" y="116" text-anchor="middle" font-size="12" fill="currentColor" >key &amp; 0x7FF</text>
</svg>
<figcaption>The three digits of a key. The top one is decided as the key arrives; the other two wait for the totals.</figcaption>
</figure>
<!-- /fig:digits -->

```csharp
// A 32-bit key is sorted as three digits. The top one picks the bucket on
// arrival; the other two are sorted privately inside the bucket afterwards.
public static int TopDigit(int key) => key >> 22;            // bits 22..31, 1,024 buckets
public static int MidDigit(int key) => (key >> 11) & 0x7FF;  // bits 11..21, second private pass
public static int LowDigit(int key) => key & 0x7FF;          // bits 0..10,  first private pass
```

```csharp
// Called on the stream's own thread with each chunk as it lands. Nothing in here needs
// the total count or any other stream: the bucket is the key's top digit, and the
// histograms are per bucket, per stream. The totals are summed once, after the last chunk.
public void Ingest(ReadOnlySpan<int> keys)
{
    if (countOnArrival)
    {
        // Refs to the first element of each histogram: Unsafe.Add skips the bounds check on
        // the two random increments per key, which is where this loop spends its time.
        ref var lowCounts = ref MemoryMarshal.GetArrayDataReference(LowDigitCounts);
        ref var midCounts = ref MemoryMarshal.GetArrayDataReference(MidDigitCounts);
        foreach (var key in keys)
        {
            var bucket = key >> Radix.TopShift;                 // top 10 bits pick the bucket
            var n = used[bucket];
            openPage[bucket][n] = key;                          // append to the bucket's open page
            if (++n == PageSize)                                // page full: file it, open a fresh one
            {
                fullPages[bucket].Add(openPage[bucket]);
                openPage[bucket] = new int[PageSize];
                n = 0;
            }
            used[bucket] = n;
            KeysPerBucket[bucket]++;
            // count the two lower digits now, so the private passes later need no counting read
            Unsafe.Add(ref lowCounts, bucket * Radix.LowRadix + (key & Radix.LowMask))++;
            Unsafe.Add(ref midCounts, bucket * Radix.LowRadix + ((key >> Radix.LowBits) & Radix.LowMask))++;
        }
        return;
    }
    // ... the same loop without the two counting lines
}
```

`PageSize` is 4,096 ints, 16 KB, so each stream has 16 MB of open pages at any time and appends are sequential within a page. `LowDigitCounts` and `MidDigitCounts` are the histograms for every bucket, flattened as `[bucket * 2048 + digit]`, 8 MB each per stream; the `Unsafe.Add` form is there because those two increments are the loop's cost, and a version with plain jagged arrays partitions 13% slower when nothing is pacing the input (and identically at 10 GbE).

## what's left after the last byte

Once every stream has stopped, the bucket sizes are the sum of each stream's counts, which gives every bucket its final range in the output. Then, per bucket, in parallel across workers: sum the streams' histograms for the bucket (2,048 adds each), scatter straight from the pages into a scratch buffer on the low 11 bits, and scatter the scratch into the bucket's final range on the next 11. Both scatters use the write-combining staging from the previous post.

```csharp
// Pass A: low digit. Read the pages in arrival order and scatter into scratch.
{
    ToOffsets(l.LowHist);                                              // histogram -> where each digit's run starts
    ref var offsets = ref MemoryMarshal.GetArrayDataReference(l.LowHist);
    ref var dest = ref MemoryMarshal.GetReference(tmp);
    ref var lines = ref MemoryMarshal.GetArrayDataReference(l.WcLines);
    ref var lineFill = ref MemoryMarshal.GetArrayDataReference(l.WcFill);
    foreach (var s in streams) foreach (var page in s.Pages(b))
        foreach (var key in page.Span) Radix.Put(ref lines, ref lineFill, ref offsets, ref dest, Radix.LowDigit(key), key);
    Radix.Drain(l.WcLines, l.WcFill, l.LowHist, tmp, Radix.LowRadix);   // flush the partial lines
}
// Pass B: middle digit. Scatter scratch into the bucket's final range. Stable, so
// keys with the same middle digit keep the low-digit order pass A gave them.
{
    ToOffsets(l.MidHist);
    ref var offsets = ref MemoryMarshal.GetArrayDataReference(l.MidHist);
    ref var dest = ref MemoryMarshal.GetReference(bucket);
    ref var lines = ref MemoryMarshal.GetArrayDataReference(l.WcLines);
    ref var lineFill = ref MemoryMarshal.GetArrayDataReference(l.WcFill);
    foreach (var key in tmp) Radix.Put(ref lines, ref lineFill, ref offsets, ref dest, Radix.MidDigit(key), key);
    Radix.Drain(l.WcLines, l.WcFill, l.MidHist, bucket, Radix.LowRadix);
}
```

`l` is the worker's reusable scratch state (one bucket's worth of temp space, the two histograms, the write-combining lines), `Radix.Put` and `Radix.Drain` are the write-combining staging from the previous post, and `ToOffsets` turns a histogram into start positions in place.

Pass A reads the pages in arrival order, so the sort is stable with respect to arrival within a stream, and streams are visited in a fixed order, so it's deterministic across them too. Peak memory is the pages (4 GB), the output (4 GB) and one scratch buffer per worker the size of its largest bucket (about 4 MB), the same two buffers the batch version needs. The difference is that a bucket's pages can be dropped the moment it's sorted, which the benchmark doesn't bother to do and a long-running node would.

## the numbers

Sixteen simulated streams, each producing its share of the keys in 1 MB chunks from a seeded generator, either as fast as the partitioner will take them or paced to an aggregate 1.25 GB/s, which is 10 GbE. Every result was checked for order and against the sum and xor of the generated keys. .NET 8 in a Linux arm64 container on an M3 Max, sixteen cores.

| a billion keys, sixteen streams | unpaced: ingest, then after last chunk | 10 GbE: ingest, then after last chunk |
|---|---:|---:|
| buffer, then `Array.Sort` (one thread) | 0.17 s, then 65.6 s | |
| buffer, then batch radix sort | 0.17 s, then 0.62 s | 3.20 s, then 0.89 s |
| partition on arrival, copy into place, sort | 0.40 s, then 0.53 s | 3.20 s, then 0.56 s |
| partition on arrival, scatter straight from pages | 0.42 s, then 0.63 s | 3.20 s, then 0.57 s |
| partition and count on arrival | 2.01 s, then 0.46 s | 3.20 s, then 0.50 s |

At 100M the same five rows run in 0.03 to 0.32 s of ingest and 0.05 to 0.12 s after the last chunk (`Array.Sort`: 6.1 s), with the same ordering.

<!-- fig:timeline -->
<figure class="diagram">
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 760 215" role="img" aria-label="Timelines at 10 GbE: buffering then sorting versus partitioning and counting on arrival, a billion keys" style="width:100%;height:auto;max-width:760px;font-family:ui-monospace,Menlo,Consolas,monospace;font-size:13px;color:var(--color-fg,currentColor)">
<defs><marker id="ah" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0L10 5L0 10z" fill="currentColor"/></marker></defs>
<line x1="200" y1="168" x2="200" y2="174" stroke="currentColor" stroke-width="1" />
<text x="200" y="188" text-anchor="middle" font-size="11" fill="currentColor" >0 s</text>
<line x1="330" y1="168" x2="330" y2="174" stroke="currentColor" stroke-width="1" />
<text x="330" y="188" text-anchor="middle" font-size="11" fill="currentColor" >1 s</text>
<line x1="460" y1="168" x2="460" y2="174" stroke="currentColor" stroke-width="1" />
<text x="460" y="188" text-anchor="middle" font-size="11" fill="currentColor" >2 s</text>
<line x1="590" y1="168" x2="590" y2="174" stroke="currentColor" stroke-width="1" />
<text x="590" y="188" text-anchor="middle" font-size="11" fill="currentColor" >3 s</text>
<line x1="720" y1="168" x2="720" y2="174" stroke="currentColor" stroke-width="1" />
<text x="720" y="188" text-anchor="middle" font-size="11" fill="currentColor" >4 s</text>
<line x1="200" y1="171" x2="746.0" y2="171" stroke="currentColor" stroke-width="1" />
<text x="188" y="62" text-anchor="end" font-size="13" fill="currentColor" >buffer, then sort</text>
<rect x="200" y="44" width="416.0" height="28" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<text x="408.0" y="62" text-anchor="middle" font-size="12" fill="currentColor" >ingest 3.20 s</text>
<rect x="616.0" y="44" width="115.69999999999993" height="28" fill="var(--color-accent, #b2570a)" fill-opacity="0.7" stroke="currentColor" stroke-width="1" />
<text x="673.85" y="62" text-anchor="middle" font-size="12" fill="currentColor" >sort 0.89</text>
<text x="188" y="122" text-anchor="end" font-size="13" fill="currentColor" >partition and count</text>
<text x="188" y="136" text-anchor="end" font-size="12" fill="currentColor" >on arrival</text>
<rect x="200" y="104" width="416.0" height="28" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<text x="408.0" y="116" text-anchor="middle" font-size="11" fill="currentColor" >ingest 3.20 s</text>
<rect x="200" y="119" width="416.0" height="13" fill="var(--color-accent, #b2570a)" fill-opacity="0.35" stroke="currentColor" stroke-width="1" />
<text x="408.0" y="129" text-anchor="middle" font-size="10" fill="currentColor" >partition + count, in idle time</text>
<rect x="616.0" y="104" width="65.0" height="28" fill="var(--color-accent, #b2570a)" fill-opacity="0.7" stroke="currentColor" stroke-width="1" />
<text x="648.5" y="122" text-anchor="middle" font-size="12" fill="currentColor" >0.50</text>
<line x1="616.0" y1="30" x2="616.0" y2="160" stroke="currentColor" stroke-width="1" stroke-dasharray="4 3"/>
<text x="616.0" y="24" text-anchor="middle" font-size="12" fill="currentColor" >last byte</text>
<text x="731.6999999999999" y="36" text-anchor="middle" font-size="11" fill="currentColor" >4.09</text>
<text x="681.0" y="96" text-anchor="middle" font-size="11" fill="currentColor" >3.70</text>
</svg>
<figcaption>A billion keys at 10 GbE. The ingest is the same 3.2 s either way; partitioning and counting ride inside it, and what is left after the last byte shrinks from 0.89 s to 0.50.</figcaption>
</figure>
<!-- /fig:timeline -->

Three things to read off it.

The batch sort is already faster than the network. At a billion keys the in-memory sort takes about 0.7 s, and a single-threaded `Array.Sort` takes 65.6 s. Once you're at radix, the ingest is the bottleneck by a factor of four, and any further work on the sort only shortens the tail after the last byte.

Partitioning on arrival is free at network speed and not free otherwise. Unpaced, the partitioner ingests slower than a memcpy because the scatter into 1,024 open pages is real work; paced to 10 GbE, the producers have time to spare and the partition rides along at no cost to the ingest.

The floor is two-thirds of the sort. Counting on arrival gets the tail to 0.46 s unpaced and 0.50 s paced, against 0.62 and 0.89 for the batch sort. The two scatters that need the totals are two of the three passes, so at most a third of the work can hide behind the ingest, and that's what hid. Counting has a price when the wire is faster than 10 GbE: the histograms are 16 MB per stream and every key does two random increments into them, which unpaced turns a 0.4 s ingest into 2.0. Scattering straight from the pages didn't beat the plain copy, because it reads the pages twice (once to count, once to scatter) through an enumerator, and that costs what the copy cost. The version to ship is the one whose extra work fits in the idle time you actually have.

## the same billion on the BEAM

For the record, the `:atomics` version from the previous post scales to a billion keys without changing: two off-heap arrays of a billion 64-bit slots (16 GB), sixteen processes each owning a range.

| a billion keys, Elixir 1.19 on OTP 28, sixteen processes | s |
|---|---:|
| fill the array from sixteen generators | 5.4 |
| `:atomics` radix, 11 bits per pass, run 1 | 9.5 |
| `:atomics` radix, 11 bits per pass, run 2 | 10.1 |

Both runs verified sorted with the input's sum. Ten seconds for a billion against 0.6 in .NET is the same fifteen-fold BIF-call-per-element gap the previous post measured at ten million, unchanged by scale. It's also an order of magnitude inside what `Enum.sort` would take (a couple of minutes, extrapolated from 10M, on a list that would itself be 16 GB), and it's the only pure-BEAM sort that gets a billion integers into order in a time you'd wait for.

The BEAM can't do the streaming variant as written, because there's no way to hand pages between processes without copying them, but the same partition-on-arrival idea maps onto per-process `:atomics` buckets sized from a first pass over the stream's own counts. That's a post of its own.

## if it doesn't fit, or must stream out

Everything above assumes the billion fits in memory and the output is wanted all at once. Drop either assumption and radix moves from being the frame to being the tool inside a different frame: sort each arriving block (with radix, since the keys are numeric), write it as a sorted run, and k-way merge the runs. That's MergeTree's parts and background merges, and DuckDB's per-thread radix sort followed by Merge Path. The merge is bandwidth-bound and parallel, and its first output row comes out immediately, which a full-pass radix sort can never offer. On disk the MSD partition survives too: 1,024 buckets are 1,024 sequential appends, which is what an external distribution sort has always been.

## what to take from it

At a billion keys of a fixed-width type, the sort is a solved problem and the network isn't: a sixteen-core radix sort beats the wire by a factor of four and the library sort by a hundred. Design for the tail after the last byte, and the way to shorten it is to do the parts of the algorithm that need no global knowledge (partition by the top digits, count the lower ones) as the data lands, leaving only the scatters that need the totals.

The production shape is sort-per-block then merge, and radix is the sort per block. That's why an analytics node can absorb a billion rows an hour with its keys in order.

## where to look

- The previous post: [Radix sort on sixteen cores, in .NET and Elixir](/radix-sort-on-sixteen-cores/), with the in-memory version this builds on and the write-combining scatter it reuses.
- Cloudflare, [HTTP Analytics for 6M requests per second using ClickHouse](https://blog.cloudflare.com/http-analytics-for-6m-requests-per-second-using-clickhouse/), 2018.
- ClickHouse, [MergeTree](https://clickhouse.com/docs/engines/table-engines/mergetree-family/mergetree): parts sorted by primary key on insert, merged in the background; and [`RadixSort.h`](https://github.com/ClickHouse/ClickHouse/blob/master/src/Common/RadixSort.h).
- Laurens Kuiper, [Fastest table sort in the West](https://duckdb.org/2021/08/27/external-sorting.html), 2021: per-thread radix sort, then Merge Path.
- Wassenberg and Sanders, [Faster Radix Sort via Virtual Memory and Write-Combining](https://arxiv.org/abs/1008.2849), 2010.
