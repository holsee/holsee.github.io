---
title: "Devlog: A Sip of CoffeeScript"
description: "Devlog notes from Code School's A Sip of CoffeeScript course."
tags:
  - codeschool
  - coffeescript
  - devlog
---

Completed the [CoffeeScript course on CodeSchool](https://www.codeschool.com/courses/coffeescript). 

<img class="center" src="/images/badges/coffeescript_badge.png" alt="">

I love these list comprehensions... I don't think I will be writing straight JS for a while.

```coffeescript
# Eat lunch.
eat food for food in ['toast', 'cheese', 'wine']

# Fine five course dining.
courses = ['greens', 'caviar', 'truffles', 'roast', 'cake']
menu i + 1, dish for dish, i in courses

# Health conscious meal.
foods = ['broccoli', 'spinach', 'chocolate']
eat food for food in foods when food isnt 'chocolate'
```


