---
layout: post
title: "Quick Sort"
date: 2014-06-25 00:24:40 +0100
comments: true
categories: Algorithms
---

<p>Quicksort, also known as <i>partition-exchange sort</i>, uses these steps.</p>

<ol>
<li> Choose any element of the array to be the pivot.</li>
<li> Divide all other elements (except the pivot) into two partitions.
<br/>- All elements less than the pivot must be in the first partition.
<br/>- All elements greater than the pivot must be in the second partition.
</li>
<li> Use recursion to sort both partitions.</li>
<li> Join the first sorted partition, the pivot, and the second sorted partition.</li>
</ol>

``` c C Quick Sort http://en.wikibooks.org/wiki/Transwiki:Quicksort#C Source
void swap(int *a, int *b) { 
  int t=*a; 
  *a=*b; 
  *b=t; 
}

void sort(int arr[], int beg, int end) {
  if (end > beg + 1) {
    int piv = arr[beg], l = beg + 1, r = end;
    while (l < r) {
      if (arr[l] <= piv) 
        l++;
      else 
        swap(&arr[l], &arr[--r]);
    }
    // swapping elements within the array 
    // to avoid the memory allocation of more arrays.
    swap(&arr[--l], &arr[beg]);
    sort(arr, beg, l);
    sort(arr, r, end);
  }
}
```

``` js JS Quick Sort http://rosettacode.org/wiki/Sorting_algorithms/Quicksort#JavaScript Source
function sort(array, less) {
 
  function swap(i, j) { 
    var t=array[i]; 
    array[i]=array[j]; 
    array[j]=t 
  }
 
  function quicksort(left, right) {
    if (left < right) {
      var pivot = array[(left + right) >> 1];
      var left_new = left, right_new = right;
      do {
        while (less(array[left_new], pivot)
          left_new++;
        while (less(pivot, array[right_new])
          right_new--;
        if (left_new  <= right_new)
          swap(left_new++, right_new--);
      } while (left_new  <= right_new);
      quicksort(left, right_new);
      quicksort(left_new, right);
    }
  }
 
  quicksort(0, array.length-1);
  return array;
}
```

``` js JS (Functional) Quick Sort http://rosettacode.org/wiki/Sorting_algorithms/Quicksort#JavaScript Source
Array.prototype.quick_sort = function ()
{
    if (this.length <= 1)
      return this;
 
    var pivot = this[Math.round(this.length / 2)];
 
    return this.filter(function (x) { return x <  pivot }).quick_sort().concat(
           this.filter(function (x) { return x == pivot })).concat(
           this.filter(function (x) { return x >  pivot }).quick_sort());
}
```

``` ruby Ruby Quick Sort http://rosettacode.org/wiki/Sorting_algorithms/Quicksort#Ruby Source
class Array
  def quick_sort
    return self if length <= 1
    pivot = sample
    group = group_by{ |x| x <=> pivot }
    group.default = []
    group[-1].quick_sort + group[0] + group[1].quick_sort
  end
end
```

``` ruby Ruby (Functional) Quick Sort http://rosettacode.org/wiki/Sorting_algorithms/Quicksort#Ruby Source
class Array
  def quick_sort
    h, *t = self
    h ? t.partition { |e| e < h }.inject { |l, r| l.quick_sort + [h] + r.quick_sort } : []
  end
end
```