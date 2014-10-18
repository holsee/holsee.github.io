---
layout: post
title: "Devlog: Real Time Web with Node.js"
date: 2014-10-07 22:00:58 +0100
comments: true
categories: nodejs codeschool devlog
---

Completed the [Real Time Web with Node.js course on CodeSchool]()

{% img /images/badges/rtnode_badge.png %}


Another impeccable course, produced to the usual  high standards which I have come to expect with each and every CodeSchool module. Go give these guys money and do a few courses, worth every penny.

I have completed a couple of node.js projects to date and am currently working on a biggin', so I didn't find this course very challenging, but I did find it fun, another great jingle and lots of great content.

The examples go a long way to show how much you can do with so little code, walking students through using [socket.io](http://socket.io) and [redis](http://redis.io) to build a chat client and a Q&A system.

Something I learned was how to use redis effectively, the course got me started and provided useful tips such as limiting size of a list to 10 items for example: 

```javascript
var redis = require("redis"),
    client = redis.createClient();
//... on last meeting submitted ...
var meeting = JSON.stringify(lastMeeting)

// Use LPUSH & LTRIM in tandem
client.lpush('recent_meetings', meeting, function(err, reply) { 
  client.ltrim('recent_meetings', 0, 9) // 10 Items Max
})
```

and for good measure, 
[using my new CoffeeScript skills](devlog-a-sip-of-coffeescript), the same thing:
```coffeescript
redis = require("redis")
client = redis.createClient()
#... on last meeting submitted ...
meeting = JSON.stringify lastMeeting

client.lpush 'recent_meetings', meeting, (err, reply) ->  
  client.ltrim('recent_meetings', 0, 9) # 10 Items Max

```

P.S. This gif of Eric Allam & Gregg Pollack cracks me up no end...

{% img center http://courseware.codeschool.com/images/blog/node-mind-blown.gif 800 800 %}