---
layout: post
title: "Merge Sort"
date: 2014-06-23 00:37:19 +0100
comments: true
categories: 
---

<p>Let n<sub>i</sub> be the number of items in the sequence to be sorted. N is number of integers that each key element can take. Let n<sub>k</sub> be the number of keys in each item.</p>

``` javascript JS Merge Sort http://en.wikibooks.org/wiki/Algorithm_Implementation/Sorting/Merge_sort Source Article
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

``` ruby Ruby Merge Sort http://en.wikibooks.org/wiki/Algorithm_Implementation/Sorting/Merge_sort Source Article
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