---
layout: post
title: "Introsort"
date: 2014-06-25 01:10:44 +0100
comments: true
categories: Algorithms
published: true
---

*Some notes on IntroSort...*


> Introsort or introspective sort is a hybrid sorting algorithm that provides both fast average performance and (asymptotically) optimal worst-case performance. It begins with quicksort and switches to heapsort when the recursion depth exceeds a level based on (the logarithm of) the number of elements being sorted. This combines the good parts of both algorithms, with practical performance comparable to quicksort on typical data sets and worst-case O(n log n) runtime due to the heap sort. Since both algorithms it uses are comparison sorts, it too is a comparison sort.
	
> Introsort was invented by David Musser in Musser (1997), in which he also introduced introselect, a hybrid selection algorithm based on quickselect (a variant of quicksort), which falls back to median of medians and thus provides worst-case linear complexity, which is optimal. Both algorithms were introduced with the purpose of providing generic algorithms for the C++ Standard Library which had both fast average performance and optimal worst-case performance, thus allowing the performance requirements to be tightened.

[Source: Wikipedia](http://en.wikipedia.org/wiki/Introsort) | [David Musser Paper 'Musser (1997)'](http://www.cs.rpi.edu/~musser/gp/algorithms.html)

### .NET 4.5 introduces Introsort in place of Quicksort

In the Microsoft .NET Framework 4.5, an Introsort implementation is used instead of simple QuickSort.

If the sort is not successfully completed, the results are undefined.
This method uses the introspective sort (introsort) algorithm as follows:
<ul>
	<li>
		If the partition size is fewer than 16 elements, it uses an <a href="http://en.wikipedia.org/wiki/Insertion_sort">insertion sort</a> algorithm.
	</li>
	<li>
		If the number of partitions exceeds 2 * Log<sub>N</sub>, where N is the range of the input array, it uses a <a href="http://en.wikipedia.org/wiki/Heapsort">Heapsort</a> algorithm.
	</li>
``` csharp .NET 4.5 IntroSort Implementation http://referencesource.microsoft.com/#mscorlib/system/array.cs#2a2126edd9ca7eb4#references Source
IntroSort(left, length + left - 1, 2 * IntrospectiveSortUtilities.FloorLog2(keys.Length));
```
	<li>
		Otherwise, it uses a <a href="http://en.wikipedia.org/wiki/Quicksort">Quicksort</a> algorithm.
	</li>
</ul>

This implementation performs an unstable sort; that is, if two elements are equal, their order might not be preserved. In contrast, a stable sort preserves the order of elements that are equal.

For arrays that are sorted by using the Heapsort and Quicksort algorithms, in the worst case, this method is an O(<sub>n</sub> log <sub>n</sub>) operation, where <sub>n</sub> is the Length of array.


You can view the full source for .NET 4.5 sorting implementation here: [.NET 4.5.1 QuickSort](http://referencesource.microsoft.com/#mscorlib/system/array.cs#60647f6f99d677f1#references)


``` csharp .NET 4.5 IntroSort Implementation http://referencesource.microsoft.com/#mscorlib/system/array.cs#2a2126edd9ca7eb4#references Source

private void IntroSort(int lo, int hi, int depthLimit)
{
    while (hi > lo)
    {
        int partitionSize = hi - lo + 1;
        if (partitionSize <= IntrospectiveSortUtilities.IntrosortSizeThreshold /* 32 */)
        {
            if (partitionSize == 1)
            {
                return;
            }
            if (partitionSize == 2)
            {
                SwapIfGreaterWithItems(lo, hi);
                return;
            }
            if (partitionSize == 3)
            {
                SwapIfGreaterWithItems(lo, hi-1);
                SwapIfGreaterWithItems(lo, hi);
                SwapIfGreaterWithItems(hi-1, hi);
                return;
            }

            InsertionSort(lo, hi);
            return;
        }

        if (depthLimit == 0)
        {
            Heapsort(lo, hi);
            return;
        }
        depthLimit--;

        int p = PickPivotAndPartition(lo, hi);
        IntroSort(p + 1, hi, depthLimit);
        hi = p - 1;
    }
}
```

You can view the latest (MIT licensed) Mono implemention on Github: [Mono.C5 Sorting.cs](https://github.com/mono/mono/blob/master/mcs/class/Mono.C5/C5/Sorting.cs)

