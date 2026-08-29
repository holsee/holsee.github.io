---
title: "Radix sort on sixteen cores, in .NET and Elixir"
description: "When radix sort is the right call and who uses it, why a radix pass parallelises and a comparison sort doesn't, the sixteen-thread version in .NET plus the write-combining tricks from the literature, the sixteen-process version in Elixir on :atomics, and Nx for the record."
tags: [personal, algorithms, dotnet, elixir, bake-off]
draft: true
---

## the short version

Use the library sort. Introsort, pdqsort, timsort: whichever yours is, it takes any comparator, has had decades of tuning, and is right almost every time. Radix sort is the special tool for one situation, and when that situation shows up nothing else is close.

Reach for it when all of these hold:

- The keys are fixed-width and there are a lot of them. Integers, floats, timestamps, ids, hashes, fixed-length strings. At a few thousand keys everything is in cache and the library sort wins on constant factors; by a million the gap in this post is already sixfold.
- The keys sit in a contiguous array: a column rather than a list of objects. Sorting objects by a property pays for the indirection and the key extraction on every access, and that swamps the inner loop.
- The order can be written as bytes. Flip the sign bit of a signed int, flip every bit of a negative float, store big-endian, and (country, year, id) becomes one byte-comparable key. If the order needs a comparator, a locale or a lambda, radix sort isn't a candidate.
- It's on a hot path: a query operator, an index build, a per-frame pass, a pipeline stage. Something that sorts all day.

Leave it alone when the input is small or nearly sorted (timsort and pdqsort go linear on existing runs; radix does its passes regardless), when keys are variable-length strings (MSD radix handles them, but it's a different algorithm with a higher crossover), when memory is tight (radix needs a second buffer of n keys; introsort needs none), when keys are wide relative to n (128-bit keys are many passes), or when you'd be maintaining it in application code. The version that wins is a few hundred lines that need a benchmark harness to keep honest, and the places that use it own it.

Those places: DuckDB radix-sorts on binary-comparable keys, one thread per block, then merges. ClickHouse keeps an LSD and an MSD radix sort for numeric columns, the MSD one for `LIMIT` queries that only need the top few percent. NumPy's stable sort is a radix sort for integers of 16 bits or less. On a GPU it's the default: CUB's `DeviceRadixSort` is an LSD radix sort over every primitive type, and the Onesweep paper made it another 1.5× faster in 2022.

## where it earns its keep: ORDER BY in a columnar database

The case I'd point at is an analytical database sorting a hundred million rows, because every condition above holds by construction. DuckDB's sort operator, as its authors described it in 2021, works like this.

First, every `ORDER BY` key is encoded into a fixed-width byte string per row. Integers are swapped to big-endian so byte order is numeric order, the sign bit is flipped so negatives sort before positives, a descending column has every bit inverted, `NULL` costs one extra byte up front, and a long string contributes a prefix, with the full string consulted only when two prefixes tie. The point of all that work is one property: `memcmp` order on the encoded keys is the query's order, and a byte-by-byte radix sort produces exactly `memcmp` order.

Second, each thread radix-sorts the rows it scanned, stably, which matters because ties in `ORDER BY` and the window functions that sit on top of it are defined by the previous order. Third, the sorted runs are merged in parallel, with Merge Path finding the cut points so that the merge itself splits across cores.

That's the pattern from this post in production shape: the keys are fixed-width because the encoder made them so, the sort is the private-then-meet-once shape, and the reason to pay for a custom sort is that it sits under every `ORDER BY`, merge join and top-N in the engine. Their numbers, from 2021: a hundred million integers in just under five seconds on one thread, and roughly three seconds in parallel, level with ClickHouse. That's far slower than the 74 ms below because an engine sorts rows, not bare ints: the payload columns travel with the keys, and the key encoding is a pass of its own. The algorithm is the same.

## why I came back to it

In March 2015 I [quoted a line from Wikipedia](/mit-introduction-to-algorithms/), "radix sorts are often, in practice, the fastest and most useful sorts on parallel machines". Eleven years and a sixteen-core laptop later, here is what it means with numbers attached. Ten million random integers: .NET's `Array.Sort` takes 525 ms, radix sort across sixteen threads takes 15, and with two tricks from a 2010 paper, 10. Elixir's `Enum.sort` takes 1.2 s, and radix sort across sixteen processes takes 101 ms. Same algorithm in both, and the interesting part is the one moment per pass where the workers have to meet.

## why a comparison sort is hard to cut up

A comparison sort is a chain of decisions: which pair you compare next depends on how the last one went. Merging two sorted lists is one front-to-back scan, and you cannot place the 500th item before the 499th. Quicksort's partition is the same shape, and its recursion tree is only balanced if the pivots are lucky, so hand two halves to two cores and one of them may get most of the work. Even on one core, the branch at every comparison is unpredictable on random data, and a mispredicted branch stalls the pipeline.

Parallel comparison sorts exist (sample sort, bitonic networks), but they either do more than n log n work or need a clever divide step to keep every core busy.

## the pass that parallelises itself

The [2015 post](/mit-introduction-to-algorithms/) has the sequential mechanism: sort on the lowest digit with a stable counting sort, then the next digit up, until you run out. That's LSD, least significant digit first, as opposed to MSD, which partitions on the top digit and recurses into each run; LSD is the one that parallelises cleanly because every pass is the same fixed amount of work over the whole input. A counting sort is three steps, and each one falls apart into independent pieces. Cut the input into one slice per core:

1. Histogram. Each core counts the digits in its own slice into its own private array. Nothing shared, nothing to branch on.
2. Prefix sum. Add the counts up in a fixed order: digit 0 from core 0, digit 0 from core 1, ... then digit 1 from core 0, and so on. Each (core, digit) pair now knows where its run starts in the output. This is the only moment the cores meet, and it's over sixteen small arrays, not n keys.
3. Scatter. Each core writes its slice into the slots it was given in step 2. No locks, because no two keys want the same slot.

Stability survives the split because of the order in step 2: every 3 from slice 0 lands before every 3 from slice 1, and inside a slice keys go out in the order they came in. Sixteen cores produce exactly the array one core would have.

<!-- fig:pass -->
<figure class="diagram">
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 760 360" role="img" aria-label="The parallel radix pass: private histograms, one prefix sum, a scatter into slots nobody else wants" style="width:100%;height:auto;max-width:760px;font-family:ui-monospace,Menlo,Consolas,monospace;font-size:13px;color:var(--color-fg,currentColor)">
<defs><marker id="ah" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0L10 5L0 10z" fill="currentColor"/></marker></defs>
<text x="10" y="22" text-anchor="start" font-size="13" fill="currentColor" font-weight="bold">1. histogram, private</text>
<text x="78" y="46" text-anchor="middle" font-size="12" fill="currentColor" >d0</text>
<text x="114" y="46" text-anchor="middle" font-size="12" fill="currentColor" >d1</text>
<text x="150" y="46" text-anchor="middle" font-size="12" fill="currentColor" >d2</text>
<text x="186" y="46" text-anchor="middle" font-size="12" fill="currentColor" >d3</text>
<text x="48" y="75" text-anchor="end" font-size="13" fill="currentColor" >w0</text>
<rect x="62" y="56" width="32" height="28" fill="#d1495b" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="78" y="75" text-anchor="middle" font-size="13" fill="currentColor" >2</text>
<rect x="98" y="56" width="32" height="28" fill="#d1495b" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="114" y="75" text-anchor="middle" font-size="13" fill="currentColor" >1</text>
<rect x="134" y="56" width="32" height="28" fill="#d1495b" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="150" y="75" text-anchor="middle" font-size="13" fill="currentColor" >1</text>
<rect x="170" y="56" width="32" height="28" fill="#d1495b" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="186" y="75" text-anchor="middle" font-size="13" fill="currentColor" >0</text>
<text x="48" y="111" text-anchor="end" font-size="13" fill="currentColor" >w1</text>
<rect x="62" y="92" width="32" height="28" fill="#2e86ab" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="78" y="111" text-anchor="middle" font-size="13" fill="currentColor" >1</text>
<rect x="98" y="92" width="32" height="28" fill="#2e86ab" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="114" y="111" text-anchor="middle" font-size="13" fill="currentColor" >2</text>
<rect x="134" y="92" width="32" height="28" fill="#2e86ab" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="150" y="111" text-anchor="middle" font-size="13" fill="currentColor" >0</text>
<rect x="170" y="92" width="32" height="28" fill="#2e86ab" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="186" y="111" text-anchor="middle" font-size="13" fill="currentColor" >1</text>
<text x="48" y="147" text-anchor="end" font-size="13" fill="currentColor" >w2</text>
<rect x="62" y="128" width="32" height="28" fill="#3a9d5d" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="78" y="147" text-anchor="middle" font-size="13" fill="currentColor" >1</text>
<rect x="98" y="128" width="32" height="28" fill="#3a9d5d" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="114" y="147" text-anchor="middle" font-size="13" fill="currentColor" >0</text>
<rect x="134" y="128" width="32" height="28" fill="#3a9d5d" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="150" y="147" text-anchor="middle" font-size="13" fill="currentColor" >2</text>
<rect x="170" y="128" width="32" height="28" fill="#3a9d5d" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="186" y="147" text-anchor="middle" font-size="13" fill="currentColor" >1</text>
<text x="48" y="183" text-anchor="end" font-size="13" fill="currentColor" >w3</text>
<rect x="62" y="164" width="32" height="28" fill="#9b5de5" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="78" y="183" text-anchor="middle" font-size="13" fill="currentColor" >2</text>
<rect x="98" y="164" width="32" height="28" fill="#9b5de5" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="114" y="183" text-anchor="middle" font-size="13" fill="currentColor" >1</text>
<rect x="134" y="164" width="32" height="28" fill="#9b5de5" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="150" y="183" text-anchor="middle" font-size="13" fill="currentColor" >0</text>
<rect x="170" y="164" width="32" height="28" fill="#9b5de5" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="186" y="183" text-anchor="middle" font-size="13" fill="currentColor" >1</text>
<text x="290" y="22" text-anchor="start" font-size="13" fill="currentColor" font-weight="bold">2. prefix sum: the one meeting</text>
<text x="358" y="46" text-anchor="middle" font-size="12" fill="currentColor" >w0</text>
<text x="402" y="46" text-anchor="middle" font-size="12" fill="currentColor" >w1</text>
<text x="446" y="46" text-anchor="middle" font-size="12" fill="currentColor" >w2</text>
<text x="490" y="46" text-anchor="middle" font-size="12" fill="currentColor" >w3</text>
<text x="330" y="75" text-anchor="end" font-size="13" fill="currentColor" >d0</text>
<rect x="340" y="56" width="36" height="28" fill="#d1495b" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="358" y="75" text-anchor="middle" font-size="13" fill="currentColor" >0</text>
<rect x="384" y="56" width="36" height="28" fill="#2e86ab" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="402" y="75" text-anchor="middle" font-size="13" fill="currentColor" >2</text>
<rect x="428" y="56" width="36" height="28" fill="#3a9d5d" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="446" y="75" text-anchor="middle" font-size="13" fill="currentColor" >3</text>
<rect x="472" y="56" width="36" height="28" fill="#9b5de5" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="490" y="75" text-anchor="middle" font-size="13" fill="currentColor" >4</text>
<text x="330" y="111" text-anchor="end" font-size="13" fill="currentColor" >d1</text>
<rect x="340" y="92" width="36" height="28" fill="#d1495b" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="358" y="111" text-anchor="middle" font-size="13" fill="currentColor" >6</text>
<rect x="384" y="92" width="36" height="28" fill="#2e86ab" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="402" y="111" text-anchor="middle" font-size="13" fill="currentColor" >7</text>
<rect x="428" y="92" width="36" height="28" fill="#3a9d5d" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="446" y="111" text-anchor="middle" font-size="13" fill="currentColor" >9</text>
<rect x="472" y="92" width="36" height="28" fill="#9b5de5" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="490" y="111" text-anchor="middle" font-size="13" fill="currentColor" >9</text>
<text x="330" y="147" text-anchor="end" font-size="13" fill="currentColor" >d2</text>
<rect x="340" y="128" width="36" height="28" fill="#d1495b" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="358" y="147" text-anchor="middle" font-size="13" fill="currentColor" >10</text>
<rect x="384" y="128" width="36" height="28" fill="#2e86ab" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="402" y="147" text-anchor="middle" font-size="13" fill="currentColor" >11</text>
<rect x="428" y="128" width="36" height="28" fill="#3a9d5d" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="446" y="147" text-anchor="middle" font-size="13" fill="currentColor" >11</text>
<rect x="472" y="128" width="36" height="28" fill="#9b5de5" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="490" y="147" text-anchor="middle" font-size="13" fill="currentColor" >13</text>
<text x="330" y="183" text-anchor="end" font-size="13" fill="currentColor" >d3</text>
<rect x="340" y="164" width="36" height="28" fill="#d1495b" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="358" y="183" text-anchor="middle" font-size="13" fill="currentColor" >13</text>
<rect x="384" y="164" width="36" height="28" fill="#2e86ab" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="402" y="183" text-anchor="middle" font-size="13" fill="currentColor" >13</text>
<rect x="428" y="164" width="36" height="28" fill="#3a9d5d" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="446" y="183" text-anchor="middle" font-size="13" fill="currentColor" >14</text>
<rect x="472" y="164" width="36" height="28" fill="#9b5de5" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="490" y="183" text-anchor="middle" font-size="13" fill="currentColor" >15</text>
<text x="428" y="212" text-anchor="middle" font-size="11" fill="currentColor" >read row by row: where each run starts</text>
<text x="10" y="212" text-anchor="start" font-size="11" fill="currentColor" >runs: 6, 4, 3, 3</text>
<text x="10" y="258" text-anchor="start" font-size="13" fill="currentColor" font-weight="bold">3. scatter: worker w writes digit d from start[d][w]</text>
<rect x="60" y="284" width="38" height="28" fill="#d1495b" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="79.0" y="303" text-anchor="middle" font-size="13" fill="currentColor" >0</text>
<text x="79.0" y="280" text-anchor="middle" font-size="10" fill="currentColor" >0</text>
<rect x="100" y="284" width="38" height="28" fill="#d1495b" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="119.0" y="303" text-anchor="middle" font-size="13" fill="currentColor" >0</text>
<text x="119.0" y="280" text-anchor="middle" font-size="10" fill="currentColor" >1</text>
<rect x="140" y="284" width="38" height="28" fill="#2e86ab" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="159.0" y="303" text-anchor="middle" font-size="13" fill="currentColor" >0</text>
<text x="159.0" y="280" text-anchor="middle" font-size="10" fill="currentColor" >2</text>
<rect x="180" y="284" width="38" height="28" fill="#3a9d5d" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="199.0" y="303" text-anchor="middle" font-size="13" fill="currentColor" >0</text>
<text x="199.0" y="280" text-anchor="middle" font-size="10" fill="currentColor" >3</text>
<rect x="220" y="284" width="38" height="28" fill="#9b5de5" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="239.0" y="303" text-anchor="middle" font-size="13" fill="currentColor" >0</text>
<text x="239.0" y="280" text-anchor="middle" font-size="10" fill="currentColor" >4</text>
<rect x="260" y="284" width="38" height="28" fill="#9b5de5" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="279.0" y="303" text-anchor="middle" font-size="13" fill="currentColor" >0</text>
<text x="279.0" y="280" text-anchor="middle" font-size="10" fill="currentColor" >5</text>
<rect x="300" y="284" width="38" height="28" fill="#d1495b" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="319.0" y="303" text-anchor="middle" font-size="13" fill="currentColor" >1</text>
<text x="319.0" y="280" text-anchor="middle" font-size="10" fill="currentColor" >6</text>
<rect x="340" y="284" width="38" height="28" fill="#2e86ab" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="359.0" y="303" text-anchor="middle" font-size="13" fill="currentColor" >1</text>
<text x="359.0" y="280" text-anchor="middle" font-size="10" fill="currentColor" >7</text>
<rect x="380" y="284" width="38" height="28" fill="#2e86ab" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="399.0" y="303" text-anchor="middle" font-size="13" fill="currentColor" >1</text>
<text x="399.0" y="280" text-anchor="middle" font-size="10" fill="currentColor" >8</text>
<rect x="420" y="284" width="38" height="28" fill="#9b5de5" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="439.0" y="303" text-anchor="middle" font-size="13" fill="currentColor" >1</text>
<text x="439.0" y="280" text-anchor="middle" font-size="10" fill="currentColor" >9</text>
<rect x="460" y="284" width="38" height="28" fill="#d1495b" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="479.0" y="303" text-anchor="middle" font-size="13" fill="currentColor" >2</text>
<text x="479.0" y="280" text-anchor="middle" font-size="10" fill="currentColor" >10</text>
<rect x="500" y="284" width="38" height="28" fill="#3a9d5d" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="519.0" y="303" text-anchor="middle" font-size="13" fill="currentColor" >2</text>
<text x="519.0" y="280" text-anchor="middle" font-size="10" fill="currentColor" >11</text>
<rect x="540" y="284" width="38" height="28" fill="#3a9d5d" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="559.0" y="303" text-anchor="middle" font-size="13" fill="currentColor" >2</text>
<text x="559.0" y="280" text-anchor="middle" font-size="10" fill="currentColor" >12</text>
<rect x="580" y="284" width="38" height="28" fill="#2e86ab" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="599.0" y="303" text-anchor="middle" font-size="13" fill="currentColor" >3</text>
<text x="599.0" y="280" text-anchor="middle" font-size="10" fill="currentColor" >13</text>
<rect x="620" y="284" width="38" height="28" fill="#3a9d5d" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="639.0" y="303" text-anchor="middle" font-size="13" fill="currentColor" >3</text>
<text x="639.0" y="280" text-anchor="middle" font-size="10" fill="currentColor" >14</text>
<rect x="660" y="284" width="38" height="28" fill="#9b5de5" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="679.0" y="303" text-anchor="middle" font-size="13" fill="currentColor" >3</text>
<text x="679.0" y="280" text-anchor="middle" font-size="10" fill="currentColor" >15</text>
<path d="M60 316 v6 H298 v-6" fill="none" stroke="currentColor" stroke-width="1"/>
<text x="179.0" y="336" text-anchor="middle" font-size="12" fill="currentColor" >digit 0</text>
<path d="M300 316 v6 H458 v-6" fill="none" stroke="currentColor" stroke-width="1"/>
<text x="379.0" y="336" text-anchor="middle" font-size="12" fill="currentColor" >digit 1</text>
<path d="M460 316 v6 H578 v-6" fill="none" stroke="currentColor" stroke-width="1"/>
<text x="519.0" y="336" text-anchor="middle" font-size="12" fill="currentColor" >digit 2</text>
<path d="M580 316 v6 H698 v-6" fill="none" stroke="currentColor" stroke-width="1"/>
<text x="639.0" y="336" text-anchor="middle" font-size="12" fill="currentColor" >digit 3</text>
<text x="60" y="352" text-anchor="start" font-size="11" fill="currentColor" >colour = worker; inside a run, worker order</text>
</svg>
<figcaption>One pass with four workers and four digit values. The only shared step is the 4 × 4 grid in the middle, and it is read digit first, worker second, which is what keeps each digit's run in worker order in the output.</figcaption>
</figure>
<!-- /fig:pass -->

Nothing about the shape depends on the data. Every core gets n/16 keys on every pass, there's no pivot to get unlucky with, and a 32-bit key is done in three passes of 11 bits (2048 buckets, so the scan is over 16 × 2048 counts). Linear work, and parallel apart from one tiny meeting per pass. That is the claim.

## .NET: threads and one array

Threads share memory, so the picture maps straight onto `Parallel.For` and one shared output array. The whole pass is the three steps above and nothing else:

```csharp
System.Threading.Tasks.Parallel.For(0, workers, w =>
{
    var local = counts[w];
    Array.Clear(local);
    var hi = Math.Min((w + 1) * chunk, n);
    for (var i = w * chunk; i < hi; i++) local[(s[i] >> sh) & mask]++;
});

var running = 0;
for (var digit = 0; digit < radix; digit++)
    for (var w = 0; w < workers; w++)
    {
        var c = counts[w][digit];
        counts[w][digit] = running;
        running += c;
    }

System.Threading.Tasks.Parallel.For(0, workers, w =>
{
    var offsets = counts[w];
    var hi = Math.Min((w + 1) * chunk, n);
    for (var i = w * chunk; i < hi; i++)
    {
        var key = s[i];
        d[offsets[(key >> sh) & mask]++] = key;
    }
});

(src, dst) = (dst, src);
```

`counts[w]` is worker w's private histogram, and the scan overwrites it in place with the same worker's start offsets, so the scatter loop needs nothing it didn't already own. `src` and `dst` swap at the end of each pass.

Ten million random non-negative 32-bit ints, medians of seven runs, .NET 8 in a Linux arm64 container on an M3 Max with sixteen cores:

| sort                          | one thread | 4 | 8 | 16 |
|-------------------------------|-----------:|----:|----:|----:|
| `Array.Sort` (introsort)      | 525 ms     |     |     |     |
| radix, 8 bits per pass        | 125        | 39  | 33  | 27  |
| radix, 11 bits per pass       | 85         | 30  | 20  | 16  |

Two things stand out. Radix on one thread already beats the library sort four to one, from the branch-free inner loop and the fixed pass count. And the scaling flattens after eight threads: each pass streams the whole array through memory twice, and sixteen cores run out of memory bandwidth long before they run out of work. That's why 11 bits beats 8: three passes instead of four is a quarter less traffic, and traffic is the ceiling. Hoisting the bounds checks with spans and refs buys another 5% (15.4 ms), which tells you the loop was already memory-bound.

### and then the literature

The version above is the textbook one. Wassenberg and Sanders got a CPU radix sort to within 12% of the machine's memory bandwidth in 2010 with three ideas, and all three port to C# without leaving managed code.

1. Reverse sorting. One MSD pass on the top ten bits partitions the input into 1,024 buckets using the shared scatter above. After that every bucket is sorted on its low 22 bits by the worker that owns it, privately, so the workers meet once instead of once per pass and the remaining passes run inside one core's cache.
2. Software write-combining. A scatter over 2,048 digits writes to 2,048 different places, which is the worst thing you can do to a cache. Instead, each digit's keys are staged in a 64-byte buffer and flushed a whole cache line at a time, so the random writes become sequential bursts. The paper flushes with non-temporal stores; .NET has no intrinsic for those on arm64, so this is the plain-store version.
3. One read for all histograms. A bucket's histograms for every remaining pass are counted in a single sweep.

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
<figcaption>How the three-pass version reads a 32-bit key: the top 10 bits choose the bucket in the one shared pass, the two 11-bit digits below it are sorted inside the bucket, privately.</figcaption>
</figure>
<!-- /fig:digits -->

The write-combining staging is one function:

```csharp
static void Put(ref int buf, ref int fill, ref int offsets, ref int dst, int digit, int key)
{
    ref var f = ref Unsafe.Add(ref fill, digit);
    Unsafe.Add(ref buf, digit * Wc + f) = key;
    if (++f == Wc)
    {
        ref var off = ref Unsafe.Add(ref offsets, digit);
        Unsafe.CopyBlockUnaligned(ref Unsafe.As<int, byte>(ref Unsafe.Add(ref dst, off)),
                                  ref Unsafe.As<int, byte>(ref Unsafe.Add(ref buf, digit * Wc)), Wc * sizeof(int));
        off += Wc;
        f = 0;
    }
}
```

`Wc` is 16 ints, one cache line. `CopyBlockUnaligned` with a constant size is inlined by the JIT into four vector stores. And the private per-bucket work, once the MSD pass has run and each worker has been handed a contiguous run of buckets balanced by key count:

<!-- fig:wc -->
<figure class="diagram">
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 760 250" role="img" aria-label="Scatter without and with software write-combining" style="width:100%;height:auto;max-width:760px;font-family:ui-monospace,Menlo,Consolas,monospace;font-size:13px;color:var(--color-fg,currentColor)">
<defs><marker id="ah" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0L10 5L0 10z" fill="currentColor"/></marker></defs>
<text x="40" y="22" text-anchor="start" font-size="13" fill="currentColor" font-weight="bold">plain scatter</text>
<text x="40" y="46" text-anchor="start" font-size="11" fill="currentColor" >keys arrive with digits 3 0 5 3 1 3 0 3</text>
<text x="40" y="62" text-anchor="start" font-size="11" fill="currentColor" >cell number = arrival order</text>
<text x="34" y="110" text-anchor="end" font-size="11" fill="currentColor" >d0</text>
<rect x="40" y="96" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="64" y="96" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="88" y="96" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="112" y="96" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="136" y="96" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="160" y="96" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="184" y="96" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="208" y="96" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="232" y="96" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="256" y="96" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<text x="34" y="134" text-anchor="end" font-size="11" fill="currentColor" >d1</text>
<rect x="40" y="120" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="64" y="120" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="88" y="120" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="112" y="120" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="136" y="120" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="160" y="120" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="184" y="120" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="208" y="120" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="232" y="120" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="256" y="120" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<text x="34" y="158" text-anchor="end" font-size="11" fill="currentColor" >d2</text>
<rect x="40" y="144" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="64" y="144" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="88" y="144" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="112" y="144" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="136" y="144" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="160" y="144" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="184" y="144" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="208" y="144" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="232" y="144" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="256" y="144" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<text x="34" y="182" text-anchor="end" font-size="11" fill="currentColor" >d3</text>
<rect x="40" y="168" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="64" y="168" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="88" y="168" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="112" y="168" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="136" y="168" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="160" y="168" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="184" y="168" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="208" y="168" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="232" y="168" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="256" y="168" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<text x="34" y="206" text-anchor="end" font-size="11" fill="currentColor" >d4</text>
<rect x="40" y="192" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="64" y="192" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="88" y="192" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="112" y="192" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="136" y="192" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="160" y="192" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="184" y="192" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="208" y="192" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="232" y="192" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="256" y="192" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<text x="34" y="230" text-anchor="end" font-size="11" fill="currentColor" >d5</text>
<rect x="40" y="216" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="64" y="216" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="88" y="216" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="112" y="216" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="136" y="216" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="160" y="216" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="184" y="216" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="208" y="216" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="232" y="216" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="256" y="216" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="40" y="168" width="22" height="18" fill="var(--color-accent, #b2570a)" fill-opacity="0.7" stroke="currentColor" stroke-width="1" />
<text x="51" y="182" text-anchor="middle" font-size="11" fill="currentColor" >1</text>
<rect x="40" y="96" width="22" height="18" fill="var(--color-accent, #b2570a)" fill-opacity="0.7" stroke="currentColor" stroke-width="1" />
<text x="51" y="110" text-anchor="middle" font-size="11" fill="currentColor" >2</text>
<rect x="40" y="216" width="22" height="18" fill="var(--color-accent, #b2570a)" fill-opacity="0.7" stroke="currentColor" stroke-width="1" />
<text x="51" y="230" text-anchor="middle" font-size="11" fill="currentColor" >3</text>
<rect x="64" y="168" width="22" height="18" fill="var(--color-accent, #b2570a)" fill-opacity="0.7" stroke="currentColor" stroke-width="1" />
<text x="75" y="182" text-anchor="middle" font-size="11" fill="currentColor" >4</text>
<rect x="40" y="120" width="22" height="18" fill="var(--color-accent, #b2570a)" fill-opacity="0.7" stroke="currentColor" stroke-width="1" />
<text x="51" y="134" text-anchor="middle" font-size="11" fill="currentColor" >5</text>
<rect x="88" y="168" width="22" height="18" fill="var(--color-accent, #b2570a)" fill-opacity="0.7" stroke="currentColor" stroke-width="1" />
<text x="99" y="182" text-anchor="middle" font-size="11" fill="currentColor" >6</text>
<rect x="64" y="96" width="22" height="18" fill="var(--color-accent, #b2570a)" fill-opacity="0.7" stroke="currentColor" stroke-width="1" />
<text x="75" y="110" text-anchor="middle" font-size="11" fill="currentColor" >7</text>
<rect x="112" y="168" width="22" height="18" fill="var(--color-accent, #b2570a)" fill-opacity="0.7" stroke="currentColor" stroke-width="1" />
<text x="123" y="182" text-anchor="middle" font-size="11" fill="currentColor" >8</text>
<text x="40" y="246" text-anchor="start" font-size="11" fill="currentColor" >8 keys, 8 writes, 4 rows</text>
<text x="420" y="22" text-anchor="start" font-size="13" fill="currentColor" font-weight="bold">write-combining</text>
<text x="420" y="46" text-anchor="start" font-size="11" fill="currentColor" >same keys, staged per digit</text>
<text x="420" y="62" text-anchor="start" font-size="11" fill="currentColor" >(4 shown, really 16): written when full</text>
<text x="414" y="110" text-anchor="end" font-size="11" fill="currentColor" >d0</text>
<rect x="420" y="96" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="444" y="96" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="468" y="96" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="492" y="96" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="516" y="96" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="540" y="96" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="564" y="96" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="588" y="96" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="612" y="96" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="636" y="96" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<text x="414" y="134" text-anchor="end" font-size="11" fill="currentColor" >d1</text>
<rect x="420" y="120" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="444" y="120" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="468" y="120" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="492" y="120" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="516" y="120" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="540" y="120" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="564" y="120" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="588" y="120" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="612" y="120" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="636" y="120" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<text x="414" y="158" text-anchor="end" font-size="11" fill="currentColor" >d2</text>
<rect x="420" y="144" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="444" y="144" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="468" y="144" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="492" y="144" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="516" y="144" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="540" y="144" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="564" y="144" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="588" y="144" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="612" y="144" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="636" y="144" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<text x="414" y="182" text-anchor="end" font-size="11" fill="currentColor" >d3</text>
<rect x="420" y="168" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="444" y="168" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="468" y="168" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="492" y="168" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="516" y="168" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="540" y="168" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="564" y="168" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="588" y="168" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="612" y="168" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="636" y="168" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<text x="414" y="206" text-anchor="end" font-size="11" fill="currentColor" >d4</text>
<rect x="420" y="192" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="444" y="192" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="468" y="192" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="492" y="192" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="516" y="192" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="540" y="192" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="564" y="192" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="588" y="192" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="612" y="192" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="636" y="192" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<text x="414" y="230" text-anchor="end" font-size="11" fill="currentColor" >d5</text>
<rect x="420" y="216" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="444" y="216" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="468" y="216" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="492" y="216" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="516" y="216" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="540" y="216" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="564" y="216" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="588" y="216" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="612" y="216" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="636" y="216" width="22" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<text x="670" y="90" text-anchor="start" font-size="11" fill="currentColor" >staging lines</text>
<rect x="670" y="96" width="12" height="18" fill="var(--color-accent, #b2570a)" fill-opacity="0.7" stroke="currentColor" stroke-width="1" />
<rect x="684" y="96" width="12" height="18" fill="var(--color-accent, #b2570a)" fill-opacity="0.7" stroke="currentColor" stroke-width="1" />
<rect x="698" y="96" width="12" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="712" y="96" width="12" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="670" y="120" width="12" height="18" fill="var(--color-accent, #b2570a)" fill-opacity="0.7" stroke="currentColor" stroke-width="1" />
<rect x="684" y="120" width="12" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="698" y="120" width="12" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="712" y="120" width="12" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="670" y="144" width="12" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="684" y="144" width="12" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="698" y="144" width="12" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="712" y="144" width="12" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="670" y="168" width="12" height="18" fill="var(--color-accent, #b2570a)" fill-opacity="0.7" stroke="currentColor" stroke-width="1" />
<rect x="684" y="168" width="12" height="18" fill="var(--color-accent, #b2570a)" fill-opacity="0.7" stroke="currentColor" stroke-width="1" />
<rect x="698" y="168" width="12" height="18" fill="var(--color-accent, #b2570a)" fill-opacity="0.7" stroke="currentColor" stroke-width="1" />
<rect x="712" y="168" width="12" height="18" fill="var(--color-accent, #b2570a)" fill-opacity="0.7" stroke="currentColor" stroke-width="1" />
<rect x="670" y="192" width="12" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="684" y="192" width="12" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="698" y="192" width="12" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="712" y="192" width="12" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="670" y="216" width="12" height="18" fill="var(--color-accent, #b2570a)" fill-opacity="0.7" stroke="currentColor" stroke-width="1" />
<rect x="684" y="216" width="12" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="698" y="216" width="12" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="712" y="216" width="12" height="18" fill="var(--color-surface, #e7e3d7)" fill-opacity="1" stroke="currentColor" stroke-width="1" />
<rect x="420" y="168" width="22" height="18" fill="var(--color-accent, #b2570a)" fill-opacity="0.7" stroke="currentColor" stroke-width="1" />
<rect x="444" y="168" width="22" height="18" fill="var(--color-accent, #b2570a)" fill-opacity="0.7" stroke="currentColor" stroke-width="1" />
<rect x="468" y="168" width="22" height="18" fill="var(--color-accent, #b2570a)" fill-opacity="0.7" stroke="currentColor" stroke-width="1" />
<rect x="492" y="168" width="22" height="18" fill="var(--color-accent, #b2570a)" fill-opacity="0.7" stroke="currentColor" stroke-width="1" />
<line x1="666" y1="177" x2="518" y2="177" stroke="currentColor" stroke-width="1" marker-end="url(#ah)" />
<text x="420" y="246" text-anchor="start" font-size="11" fill="currentColor" >8 keys, 1 write so far (the full line)</text>
</svg>
<figcaption>Eight keys with digits 3 0 5 3 1 3 0 3. Without staging, each is a write to wherever its digit's run happens to be; with staging, a digit's keys wait in a 64-byte line and leave together.</figcaption>
</figure>
<!-- /fig:wc -->

```csharp
for (var b = firstBucket; b < lastBucket; b++)
{
    int lo = bucketStart[b], len = bucketStart[b + 1] - lo;
    if (len <= 1) continue;
    var bucket = dst.AsSpan(lo, len);
    var tmp = scratch.AsSpan(0, len);

    // all this bucket's histograms from one read
    for (var p = 0; p < passes; p++) Array.Clear(hists[p]);
    foreach (var key in bucket)
        for (var p = 0; p < passes; p++) hists[p][(key >> (p * localBits)) & mask]++;

    Span<int> src = bucket, dstSpan = tmp;
    for (var p = 0; p < passes; p++)
    {
        LocalPass(src, dstSpan, hists[p], p * localBits, mask, radix, buf, fill);
        var swap = src; src = dstSpan; dstSpan = swap;
    }
    if (passes % 2 == 1) tmp.CopyTo(bucket);   // odd pass count ends in scratch
}
```

The scratch buffer, histograms and write-combine buffers are allocated once per worker and reused across its buckets. Same container, medians of seven runs at 10M and three at 100M:

| | 10M, 1 thread | 10M, 16 | 100M, 1 | 100M, 16 |
|---|---:|---:|---:|---:|
| `Array.Sort` | 533 ms | | 6,057 ms | |
| LSD, shared scatter each pass | 94 | 15.2 | 1,009 | 121 |
| MSD, then private LSD per bucket | 87 | 11.9 | 886 | 115 |
| the same, with write-combining | 60 | 10.1 | 604 | 74 |

Write-combining is worth 1.5× on a single thread, which is the paper's number, and the bigger the array the more it matters on sixteen: 1.2× at 10M, 1.6× at 100M, because the cost it removes is the scatter's random writes missing cache, and a 400 MB destination misses more. A hundred million ints in 74 ms is 82× `Array.Sort`.

## Elixir: processes and `:atomics`

There's no shared array to start from on the BEAM: process heaps are private and a message is a copy into the receiver's heap. Lists and maps in messages would put a copy of every key on every pass, and the copying would cost more than the bucketing. What the runtime does have is `:atomics` (OTP 21.2): an off-heap array of 64-bit integers, referenced like a binary and shared between processes by reference, with atomic `get`, `put`, `add` and `add_get`. It's the C array this algorithm was written for. Two n-slot arrays as source and destination, swapped each pass; each worker's histogram and offsets in a small `:atomics` of its own, so the inner loops allocate nothing. The pass:

<!-- fig:beam -->
<figure class="diagram">
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 760 285" role="img" aria-label="Sixteen BEAM processes with private heaps sharing two off-heap atomics arrays" style="width:100%;height:auto;max-width:760px;font-family:ui-monospace,Menlo,Consolas,monospace;font-size:13px;color:var(--color-fg,currentColor)">
<defs><marker id="ah" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0L10 5L0 10z" fill="currentColor"/></marker></defs>
<rect x="40" y="20" width="150" height="78" fill="#d1495b" fill-opacity="0.2" stroke="currentColor" stroke-width="1" />
<text x="115" y="40" text-anchor="middle" font-size="12" fill="currentColor" font-weight="bold">process 0</text>
<text x="115" y="56" text-anchor="middle" font-size="11" fill="currentColor" >private heap</text>
<rect x="55" y="64" width="120" height="24" fill="#d1495b" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="115" y="80" text-anchor="middle" font-size="10" fill="currentColor" >:atomics[2048]</text>
<rect x="220" y="20" width="150" height="78" fill="#2e86ab" fill-opacity="0.2" stroke="currentColor" stroke-width="1" />
<text x="295" y="40" text-anchor="middle" font-size="12" fill="currentColor" font-weight="bold">process 1</text>
<text x="295" y="56" text-anchor="middle" font-size="11" fill="currentColor" >private heap</text>
<rect x="235" y="64" width="120" height="24" fill="#2e86ab" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="295" y="80" text-anchor="middle" font-size="10" fill="currentColor" >:atomics[2048]</text>
<rect x="400" y="20" width="150" height="78" fill="#3a9d5d" fill-opacity="0.2" stroke="currentColor" stroke-width="1" />
<text x="475" y="40" text-anchor="middle" font-size="12" fill="currentColor" font-weight="bold">process 2</text>
<text x="475" y="56" text-anchor="middle" font-size="11" fill="currentColor" >private heap</text>
<rect x="415" y="64" width="120" height="24" fill="#3a9d5d" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="475" y="80" text-anchor="middle" font-size="10" fill="currentColor" >:atomics[2048]</text>
<rect x="580" y="20" width="150" height="78" fill="#9b5de5" fill-opacity="0.2" stroke="currentColor" stroke-width="1" />
<text x="655" y="40" text-anchor="middle" font-size="12" fill="currentColor" font-weight="bold">process 3</text>
<text x="655" y="56" text-anchor="middle" font-size="11" fill="currentColor" >private heap</text>
<rect x="595" y="64" width="120" height="24" fill="#9b5de5" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="655" y="80" text-anchor="middle" font-size="10" fill="currentColor" >:atomics[2048]</text>
<text x="40" y="276" text-anchor="start" font-size="12" fill="currentColor" >both arrays off-heap, shared by reference, never copied</text>
<text x="30" y="150" text-anchor="end" font-size="12" fill="currentColor" >src</text>
<rect x="40" y="130" width="170" height="30" fill="#d1495b" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="125" y="150" text-anchor="middle" font-size="11" fill="currentColor" >slice 0, process 0</text>
<line x1="115" y1="100" x2="125" y2="128" stroke="currentColor" stroke-width="1" marker-end="url(#ah)" />
<rect x="210" y="130" width="170" height="30" fill="#2e86ab" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="295" y="150" text-anchor="middle" font-size="11" fill="currentColor" >slice 1, process 1</text>
<line x1="295" y1="100" x2="295" y2="128" stroke="currentColor" stroke-width="1" marker-end="url(#ah)" />
<rect x="380" y="130" width="170" height="30" fill="#3a9d5d" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="465" y="150" text-anchor="middle" font-size="11" fill="currentColor" >slice 2, process 2</text>
<line x1="475" y1="100" x2="465" y2="128" stroke="currentColor" stroke-width="1" marker-end="url(#ah)" />
<rect x="550" y="130" width="170" height="30" fill="#9b5de5" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<text x="635" y="150" text-anchor="middle" font-size="11" fill="currentColor" >slice 3, process 3</text>
<line x1="655" y1="100" x2="635" y2="128" stroke="currentColor" stroke-width="1" marker-end="url(#ah)" />
<text x="30" y="220" text-anchor="end" font-size="12" fill="currentColor" >dst</text>
<rect x="40" y="200" width="80.5" height="30" fill="#d1495b" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<rect x="120.5" y="200" width="46.0" height="30" fill="#2e86ab" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<rect x="166.5" y="200" width="69.0" height="30" fill="#3a9d5d" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<rect x="235.5" y="200" width="34.5" height="30" fill="#9b5de5" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<path d="M40 234 v6 H270 v-6" fill="none" stroke="currentColor" stroke-width="1"/>
<text x="155.0" y="254" text-anchor="middle" font-size="11" fill="currentColor" >digit 0 run</text>
<rect x="270" y="200" width="59.49999999999999" height="30" fill="#d1495b" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<rect x="329.5" y="200" width="34.0" height="30" fill="#2e86ab" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<rect x="363.5" y="200" width="51.0" height="30" fill="#3a9d5d" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<rect x="414.5" y="200" width="25.5" height="30" fill="#9b5de5" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<path d="M270 234 v6 H440 v-6" fill="none" stroke="currentColor" stroke-width="1"/>
<text x="355.0" y="254" text-anchor="middle" font-size="11" fill="currentColor" >digit 1 run</text>
<rect x="440" y="200" width="52.5" height="30" fill="#d1495b" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<rect x="492.5" y="200" width="30.0" height="30" fill="#2e86ab" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<rect x="522.5" y="200" width="45.0" height="30" fill="#3a9d5d" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<rect x="567.5" y="200" width="22.5" height="30" fill="#9b5de5" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<path d="M440 234 v6 H590 v-6" fill="none" stroke="currentColor" stroke-width="1"/>
<text x="515.0" y="254" text-anchor="middle" font-size="11" fill="currentColor" >digit 2 run</text>
<rect x="590" y="200" width="45.5" height="30" fill="#d1495b" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<rect x="635.5" y="200" width="26.0" height="30" fill="#2e86ab" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<rect x="661.5" y="200" width="39.0" height="30" fill="#3a9d5d" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<rect x="700.5" y="200" width="19.5" height="30" fill="#9b5de5" fill-opacity="0.45" stroke="currentColor" stroke-width="1" />
<path d="M590 234 v6 H720 v-6" fill="none" stroke="currentColor" stroke-width="1"/>
<text x="655.0" y="254" text-anchor="middle" font-size="11" fill="currentColor" >digit 3 run</text>
<text x="40" y="186" text-anchor="start" font-size="12" fill="currentColor" >one block per process per digit run, in worker order</text>
</svg>
<figcaption>The shape on the BEAM: private heaps, private histograms, and two off-heap <code>:atomics</code> arrays that every process can reach without a copy. Each process reads its slice of <code>src</code> and writes its own block in every digit run of <code>dst</code>.</figcaption>
</figure>
<!-- /fig:beam -->

```elixir
hists =
  ranges
  |> Enum.map(fn {lo, hi} -> Task.async(fn -> h = :atomics.new(radix, []); histogram(src, lo, hi, shift, mask, h); h end) end)
  |> Enum.map(&Task.await(&1, :infinity))

Enum.reduce(0..(radix - 1), 1, fn d, running ->
  Enum.reduce(hists, running, fn h, running ->
    c = :atomics.get(h, d + 1)
    :atomics.put(h, d + 1, running)
    running + c
  end)
end)

ranges
|> Enum.zip(hists)
|> Enum.map(fn {{lo, hi}, off} -> Task.async(fn -> scatter(src, dst, lo, hi, shift, mask, off) end) end)
|> Enum.each(&Task.await(&1, :infinity))
```

Same three steps as the C#, same in-place scan turning each worker's histogram into its offsets. The scatter loop is five BIF calls per key and nothing else:

```elixir
defp scatter(_src, _dst, lo, hi, _shift, _mask, _off) when lo > hi, do: :ok
defp scatter(src, dst, lo, hi, shift, mask, off) do
  x = :atomics.get(src, lo)
  pos = :atomics.add_get(off, ((x >>> shift) &&& mask) + 1, 1) - 1
  :atomics.put(dst, pos, x)
  scatter(src, dst, lo + 1, hi, shift, mask, off)
end
```

`add_get` bumps the offset for that digit and returns the new value, so `pos` is this key's slot and the next key with the same digit gets the one after. The offsets array is the worker's own and the slots it writes are disjoint from every other worker's by construction, so there is nothing to lock and no compare-and-swap anywhere.

Ten million keys, medians of five, Elixir 1.19 on OTP 27, same machine:

| sort                           | one process | 4 | 8 | 16 |
|--------------------------------|------------:|----:|----:|----:|
| `Enum.sort` (merge sort)       | 1,199 ms    |     |     |     |
| `:atomics` radix, 8 bits       | 1,087       | 290 | 154 | 124 |
| `:atomics` radix, 11 bits      | 843         | 256 | 137 | 101 |

Twelve times faster than `Enum.sort`, and the same shape as the .NET curve: 11 bits beats 8, and sixteen workers give 8.3× over one. Loading the keys from a binary into the array is 13 ms with sixteen workers each filling their own range, and reading the sorted array back out to a binary is 12, so a process that receives ten million ints as bytes can hand back sorted bytes in about 130 ms.

The one-core gap to .NET (843 ms against 85) is the price of the runtime: every `:atomics` call is a BIF call at tens of nanoseconds, where the C# loop does a memory access. Parallelism buys most of that back. The only way to buy the rest is a NIF, and at that point you are writing the C# version in Rust.

### Nx, for the record

If the keys are already a tensor, there's a one-liner. A tensor is a contiguous binary, and `Nx.sort` on the EXLA backend hands that buffer to compiled XLA code:

```elixir
t = Nx.from_binary(bin, :s32, backend: EXLA.Backend)
sorted = Nx.sort(t)
```

192 ms for ten million keys and 17 for a million, without the BEAM touching an element. It's a comparison sort on one core (I sampled the OS process while it looped: 104% CPU), so it's six times faster than `Enum.sort` and still behind the sixteen-process `:atomics` version, and getting a list into a tensor and back (336 and 382 ms at 10M) costs more than the sort. On a CUDA GPU the same call dispatches to a radix sort, which is the parallel machine the Wikipedia line was written about.

## the two runtimes, side by side

Ten million random 32-bit ints on the same sixteen cores:

| | library sort | radix, one core | radix, 16 cores | with write-combining, 16 cores |
|---|---:|---:|---:|---:|
| .NET 8 | 533 ms | 94 | 15 | 10 |
| Elixir (`:atomics`) | 1,199 ms | 843 | 101 | |
| Elixir (`Nx.sort`, EXLA, one core) | 192 ms | | | |

## what to take from it

The parallelism is in the algorithm's shape. A radix pass is private histograms, one tiny meeting, and a scatter into slots nobody else wants, and that shape survives any runtime that can give sixteen workers one mutable array. Past eight cores the ceiling is memory bandwidth, so fewer passes beats more threads, and the literature's tricks are all ways of touching memory less: meet once, then stay in cache; stage writes into cache lines.

On the BEAM the array is the design decision. Anything that crosses a process boundary by value pays a copy per key per pass; `:atomics` is the shared mutable array that doesn't, and it carries this algorithm to within a runtime constant of the C#.

## where to look

- The 2015 post this follows on from: [MIT: Introduction to Algorithms](/mit-introduction-to-algorithms/), with the sequential mechanism and the decimal-digit versions in C# and Elixir.
- The next post: [Sorting a billion integers from a stream](/sorting-a-billion-integers-from-a-stream/), the same sort at the scale where the network is the bottleneck.
- The lecture: [6.006 Counting Sort, Radix Sort, Lower Bounds for Sorting](https://www.youtube.com/watch?v=Nz1KZXbghj8) on MIT OpenCourseWare.
- Zagha and Blelloch, "Radix sort for vector multiprocessors", Supercomputing '91: the paper behind the Wikipedia line.
- Laurens Kuiper, [Fastest table sort in the West: redesigning DuckDB's sort](https://duckdb.org/2021/08/27/external-sorting.html), 2021: binary-comparable keys, per-thread radix sort, Merge Path.
- ClickHouse's [`RadixSort.h`](https://github.com/ClickHouse/ClickHouse/blob/master/src/Common/RadixSort.h): LSD stable and MSD partial, with the sign and float bit transforms in the header comment.
- NumPy's [1.17 release notes](https://numpy.org/doc/stable/release/1.17.0-notes.html): radix sort for integer types of 16 bits or less under `kind="stable"`.
- CUB's [`DeviceRadixSort`](https://nvidia.github.io/cccl/cub/api/structcub_1_1DeviceRadixSort.html) and Adinets and Merrill, [Onesweep: a faster least significant digit radix sort for GPUs](https://arxiv.org/abs/2206.01784), 2022.
- Jan Wassenberg and Peter Sanders, [Faster Radix Sort via Virtual Memory and Write-Combining](https://arxiv.org/abs/1008.2849), 2010: reverse sorting and software write-combining, with the bandwidth measurements.
- Satish et al., "Fast sort on CPUs and GPUs: a case for bandwidth oblivious SIMD sort", SIGMOD 2010: the Intel radix sort the paper above beats by 1.5×.
- Marc Gravell, [Sorting myself out, extreme edition](https://blog.marcgravell.com/2018/01/sorting-myself-out-extreme-edition.html), 2018: radix sort in C# on `Span<T>`.
- [HPCsharp](https://github.com/DragonSpit/HPCsharp): a C# library with parallel radix sorts, if you'd rather not maintain your own.
- Erlang's [`atomics`](https://www.erlang.org/doc/apps/erts/atomics.html) module.
- [Nx](https://github.com/elixir-nx/nx) and the EXLA backend.
