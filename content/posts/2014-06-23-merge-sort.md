---
title: "Merge Sort"
description: "Notes on merge sort: split until trivial, merge back with two queues, and why that lands on n log n."
tags:
  - algorithms
---

*Some notes on merge sort...*

You start with an unordered sequence.
If it has one item (or none) it is already sorted, so hand it back.
Otherwise split it down the middle and merge sort each half.
Now you have two sorted halves, and merging them is the easy part: treat each half as a queue, compare the two items at the front, and move the smaller one into the result.
Keep doing that until one queue runs dry, then tack whatever is left of the other one onto the end.
Because you only ever take the smaller front item, the result is sorted, and because you take from the left queue on a tie, the sort is stable.

Let n be the number of items. Splitting in half over and over gives you log<sub>2</sub> n levels of recursion, and each level does one merge pass over all n items in total.

The total time to sort the sequence is thus O(n log n), for any input, which is the thing merge sort has over quicksort.

```javascript
function mergesort(list){
  if (list.length <= 1)
    return list;
 
  var mid = Math.floor(list.length / 2),
    left  = list.slice(0, mid),
    right = list.slice(mid, list.length);
 
  return merge(mergesort(left), mergesort(right))
}
 
function merge(left, right){
  var sorted = [];
  while (left && left.length > 0 && right && right.length > 0){
    var b = left[0] <= right[0];
    sorted.push(b? left[0]: right[0]);
    // remove the element which was added to the sorted array
    b? left.splice(0, 1): right.splice(0, 1);
  }
  return sorted.concat(left, right);
}
```

```ruby
def mergesort(list)
  return list if list.size <= 1
  mid = list.size / 2
  left  = list[0, mid]
  right = list[mid, list.size-mid]
  merge(mergesort(left), mergesort(right))
end
 
def merge(left, right)
  sorted = []
  until left.empty? or right.empty?
    if left.first <= right.first
      sorted << left.shift
    else
      sorted << right.shift
    end
  end
  sorted.concat(left).concat(right)
end
```