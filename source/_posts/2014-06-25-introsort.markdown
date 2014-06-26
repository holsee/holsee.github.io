---
layout: post
title: "Introsort"
date: 2014-06-25 01:10:44 +0100
comments: true
categories: 
published: true
---

Introsort or introspective sort is a hybrid sorting algorithm that provides both fast average performance and (asymptotically) optimal worst-case performance. It begins with quicksort and switches to heapsort when the recursion depth exceeds a level based on (the logarithm of) the number of elements being sorted. This combines the good parts of both algorithms, with practical performance comparable to quicksort on typical data sets and worst-case O(<sub>n</sub> log <sub>n</sub>) runtime due to the heap sort. Since both algorithms it uses are comparison sorts, it too is a comparison sort.


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
	<li>
		Otherwise, it uses a <a href="http://en.wikipedia.org/wiki/Quicksort">Quicksort</a> algorithm.
	</li>
</ul>

This implementation performs an unstable sort; that is, if two elements are equal, their order might not be preserved. In contrast, a stable sort preserves the order of elements that are equal.

For arrays that are sorted by using the Heapsort and Quicksort algorithms, in the worst case, this method is an O(<sub>n</sub> log <sub>n</sub>) operation, where <sub>n</sub> is the Length of array.


Compare this to the Mono Implementation:
https://github.com/mono/mono/blob/master/mcs/class/Mono.C5/C5/Sorting.cs