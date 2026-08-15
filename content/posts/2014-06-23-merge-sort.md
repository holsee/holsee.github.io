---
title: "Merge Sort"
description: "Notes on merge sort: the queue-based mental model, the steps, and the complexity."
tags:
  - algorithms
---

You start with an unordered sequence. 
You create N empty queues. 
You loop over every item to be sorted. 
On each loop iteration, you look at the last element in the key. 
You move that item into the end of the queue which corresponds to that element. 
When you are finished looping you concatenate all the queues together into another sequence. 
You then reapply the procedure described but look at the second last element in the key. 
You keep doing this until you have looped over every key. 
When you complete this process the resulting sequence will be sorted as described above.

<p>Let n<sub>i</sub> be the number of items in the sequence to be sorted. N is number of integers that each key element can take. Let n<sub>k</sub> be the number of keys in each item.</p>
<p>The total time to sort the sequence is thus O(n<sub>k</sub>(n<sub>i</sub> + N)).</p>

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