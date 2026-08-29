---
title: "MIT: Introduction to Algorithms"
description: "Radix sort, how it gets past the n log n floor, and the MIT 6.006 lecture worth revisiting, with a walkthrough in C# and Elixir."
tags:
  - algorithms
  - comp-sci
  - dotnet
  - elixir
---

I got into a conversation this week about that computer science classic, sorting, and in particular where radix sort gets used in practice. It is not an algorithm I have ever needed to reach for, so it had been filed under "clever, but niche". Then this line from the Wikipedia article caught my eye:

> Radix sorts are often, in practice, the fastest and most useful sorts on parallel machines.

Fastest? A sort I have never once used in anger? That was enough to send me back to the fundamentals, and my favourite place for those is the MIT course [Introduction to Algorithms](http://ocw.mit.edu/courses/electrical-engineering-and-computer-science/6-006-introduction-to-algorithms-fall-2011/lecture-videos/) (6.006). It covers the basics properly and the lectures are free.

The one I am watching at the minute is "Counting Sort, Radix Sort, Lower Bounds for Sorting":

::video{youtube="Nz1KZXbghj8" title="MIT 6.006: Counting Sort, Radix Sort, Lower Bounds for Sorting"}

## why radix sort gets to skip the queue

Every sort I use day to day (quicksort, merge sort, the introsort in your standard library) works by comparing pairs of keys, and the lecture opens by proving that no comparison sort can beat n log n. The argument is lovely. A comparison sort is a decision tree: each comparison is a branch, each leaf is a final ordering. There are n! orderings it must be able to tell apart, so the tree needs n! leaves, so its height (the number of comparisons on the worst path) is at least log2(n!), which works out at roughly n log n.

Radix sort never compares two keys. It looks at one digit of each key at a time and deals the keys into buckets, and dealing into buckets is a counting sort, which is linear. With d digits and a radix of k (the number of values a digit can take), the whole job costs O(d · (n + k)). Sort 32-bit integers a byte at a time and that is four passes of O(n + 256), which is why it wins on big arrays of fixed-width keys. Each pass is a histogram, a prefix sum and a scatter, and those parallelise a lot more happily than a comparison tree does. Hence the quote.

## the mechanism

The version everyone means is least-significant-digit radix sort:

1. Find the largest key, so you know how many digits there are to look at.
2. Starting with the units digit, sort the whole list on that digit alone, *stably*.
3. Move one digit to the left and go again, until you have gone past the top digit of the largest key.

Take `[170, 45, 75, 90, 802, 24, 2, 66]`:

| pass | digit    | list after the pass                 |
|------|----------|-------------------------------------|
| 1    | units    | 170, 90, 802, 2, 24, 45, 75, 66     |
| 2    | tens     | 802, 2, 24, 45, 66, 170, 75, 90     |
| 3    | hundreds | 2, 24, 45, 66, 75, 90, 170, 802     |

The whole trick is in the word stable. A stable sort keeps keys that tie in the order they arrived. After the units pass the list is in units order. The tens pass only moves keys whose tens digits differ; keys with the same tens digit keep their relative order, which is already units order. So after two passes the list is sorted on its last two digits, after three on its last three, and by the time you run out of digits it is sorted. Lose the stability and the earlier passes are wasted work.

Notice that `2` ends up ahead of `24` after the tens pass even though it has no tens digit. A missing digit is a zero, so shorter keys fall out in front, which is exactly what you want.

Both implementations below sort non-negative integers a decimal digit at a time, because that is the easiest version to read next to the table. For real work you would take a byte per pass instead (radix 256) and handle the sign bit, but the shape is identical.

## in C#

The inner sort is a counting sort in three loops: count how many keys have each digit, turn the counts into starting offsets, then scatter each key into its digit's next free slot.

```csharp
using System.Linq;

public static class RadixSort
{
    public static int[] Sort(int[] items)
    {
        if (items.Length == 0) return items;

        var max = items.Max();
        var sorted = items;

        // One pass per decimal digit of the largest key, units first.
        for (long divisor = 1; max / divisor > 0; divisor *= 10)
            sorted = CountingSortByDigit(sorted, divisor);

        return sorted;
    }

    private static int[] CountingSortByDigit(int[] items, long divisor)
    {
        // 1. Histogram: how many keys have each digit?
        var counts = new int[10];
        foreach (var item in items)
            counts[Digit(item, divisor)]++;

        // 2. Prefix sum: where does each digit's run start in the output?
        var offsets = new int[10];
        for (var d = 1; d < 10; d++)
            offsets[d] = offsets[d - 1] + counts[d - 1];

        // 3. Scatter: drop each key into its digit's next free slot.
        //    Walking the input in order is what makes this stable.
        var output = new int[items.Length];
        foreach (var item in items)
            output[offsets[Digit(item, divisor)]++] = item;

        return output;
    }

    private static int Digit(int item, long divisor)
    {
        return (int)(item / divisor % 10);
    }
}
```

```csharp
RadixSort.Sort(new[] { 170, 45, 75, 90, 802, 24, 2, 66 });
// 2, 24, 45, 66, 75, 90, 170, 802
```

The `offsets` array is the clever bit. If three keys have a units digit of 0 and two have a units digit of 2, then the 2s must start at index 3 in the output, and every time you place one you bump its offset along by one (`offsets[...]++`). Because the input is walked front to back, two keys with the same digit land in the output in the same order they were read. That is the stability the whole algorithm leans on, and it costs nothing extra.

The `divisor` is a `long` rather than an `int` for a boring reason: for keys near `int.MaxValue` it has to reach 10<sup>10</sup> before the loop condition notices it is done, and that does not fit in 32 bits.

## in Elixir

Same algorithm, functional shape. The output array becomes a value that falls out of a pipe, and the `for` loop becomes recursion.

```elixir
defmodule RadixSort do
  def sort([]), do: []
  def sort(items), do: sort(items, 1, Enum.max(items))

  # Done once the divisor has moved past the top digit of the largest key.
  defp sort(items, divisor, max) when div(max, divisor) == 0, do: items

  defp sort(items, divisor, max) do
    items
    |> bucket_by_digit(divisor)
    |> sort(divisor * 10, max)
  end

  # One stable pass: deal each key into the bucket for its digit, then
  # read the buckets back out in digit order.
  defp bucket_by_digit(items, divisor) do
    buckets =
      Enum.reduce(items, %{}, fn item, acc ->
        Map.update(acc, digit(item, divisor), [item], &[item | &1])
      end)

    Enum.flat_map(0..9, fn d ->
      buckets |> Map.get(d, []) |> Enum.reverse()
    end)
  end

  defp digit(item, divisor), do: rem(div(item, divisor), 10)
end
```

```elixir
iex> RadixSort.sort([170, 45, 75, 90, 802, 24, 2, 66])
[2, 24, 45, 66, 75, 90, 170, 802]
```

If you have never seen Elixir, a few things are going on here that are worth a sentence each.

A function can have several clauses and the runtime picks the first one whose pattern matches, so `sort([])` handles the empty list and `sort(items)` handles everything else. The three-argument `sort/3` is private (`defp`) and does the looping: the `when div(max, divisor) == 0` guard is the loop's exit condition, and the clause below it is the loop body, which calls itself with the divisor multiplied by ten. The `|>` pipe feeds the value on its left in as the first argument of the call on its right, so `items |> bucket_by_digit(divisor) |> sort(divisor * 10, max)` reads top to bottom as "bucket, then recurse".

`bucket_by_digit` is the counting sort. `Enum.reduce` folds over the list carrying an accumulator, here a map (`%{}`) from digit to bucket. `Map.update(map, key, default, fun)` inserts the default if the key is missing and otherwise applies the function to the existing value, and `&[item | &1]` is shorthand for `fn bucket -> [item | bucket] end`, which prepends. Elixir lists are linked lists, so prepending is constant time and appending is not, which is why each bucket is built back to front and then flipped once with `Enum.reverse` as it is read out. Reading the buckets out in `0..9` order and flattening them with `Enum.flat_map` gives you the stable pass.

Two small things I enjoyed. There is no mutation anywhere, so there is nothing to clone up front to protect the caller's list; every pass hands back a fresh one. And Elixir integers are arbitrary precision, so the `long` fudge from the C# version simply does not come up: the divisor can grow as large as it likes.

A good start for now. Next on the list is where radix sort actually earns its keep, and this question on [Practical Applications of Radix Sort](http://cs.stackexchange.com/questions/12223/practical-applications-of-radix-sort) is a decent thread to pull on.

## where to look

- The [6.006 lecture videos](http://ocw.mit.edu/courses/electrical-engineering-and-computer-science/6-006-introduction-to-algorithms-fall-2011/lecture-videos/) on MIT OpenCourseWare.
- [Practical Applications of Radix Sort](http://cs.stackexchange.com/questions/12223/practical-applications-of-radix-sort) on the Computer Science Stack Exchange.
