---
layout: post
title: "Devlog: What I've Been Learning"
date: 2014-09-24 00:00:00 +0100
comments: true
categories: devlog
published: true
---

These last few months I have been learning more than usual and in this post I talk a little about some of the things that have caught my interest.  All of this is outside of work as my day job is working on a Trading platform written in C#.

Another goal of this post is to kick start my blogging again which I have completely got out of the way of doing over the last 2 or so years.  

### Erlang & Elixir

Partially inspired by my functional programming binge and a chat I had with [Joe Armstrong](http://joearms.github.io) at [ReactConf](http://reactconf.com); I have been getting stuck into Erlang, [Elixir](http://elixir-lang.org) and the [Phoenix web framework](https://github.com/phoenixframework/phoenix).  

I feel these will play a big part in my future.  The BEAM VM is fascinating and the powerful distributed programming model via the OTP libraries is something different and interesting.  I look forward to digging into these topics on my blog in the coming months as I become more familiar with them.  

I am working on an 'anonymous' location broadcast server to use these technologies in anger and I have found this has helped me achieve those A-HA moments that are so important when it comes to learning something and making it stick.

### Node.js

I've been working away on a personal project (which will be launched at outloud.io some time in the future) using node.js, express.js, postgreSQL, passport.js, mocha, chai, chai-as-promised, Q, db-migrate, node-env...  

I have had this idea for a while, and I got pretty excited about building it.  At the time I was looking for a good excuse to get stuck into a substantial project which was built on node.js.  Even though I have used JS for years I have learned a great deal about the node way, building stuff tis the best way to learn it is no secret.

### Ruby and Rails

I completed a MOOC course on Coursera on [Web Application Architectures](https://www.coursera.org/course/webapplications) which used Ruby & Rails recently.  Was very much entry level stuff, got through it in about 2 days and I think anybody with significant web dev experiences would find the same thing.  I guess it showed me that I knew more than I thought about Ruby and Rails and needed to focus on more advanced and newer topics.

I have been slowly but surely learning Ruby for the past 4 years and I find it lots of fun.  I used to subscribe and watch the [Ruby Tapas](http://www.rubytapas.com) episodes which are brilliant, but because I wasn't using it in my day job for anything more than Chef scripts I never really got to go deep.

[Codewars.com](http://www.codewars.com/about) stole quite a few of my evenings, a great way to learn or get better using a language by solving a katas (with tests) then seeing how others solved the same problems in a potentially more idiomatic way.  Each solution is rated by the community on 'how smart' and 'best practice' which is a nice touch.

I plan to dig into the latest version of Rails for Zombies on Code School and keep going to the [Belfast Ruby](http://belfastruby.com) meet-ups.

### Objective-C

I worked as a "mobile developer" and have built a few apps over the last number of years in various technologies such as Obj-C, Java (Android), C# Xamarin (targeting both iOS and Android) and some PoCs using Phonegap. 

But I never felt I got to use Objective-C to the extent I wanted to, as the performance, the sexy runtime dispatch and the CocoaTouch libs intrigued.  A friend of mine who now works at Apple once told me the Cocoa libraries were examples of some of the nicest Object Oriented programming he had ever seen.  This has always made me want to know more.

My employer sent me on an Objective-C course few months back which was nice of them since I don't even use it in my current day job.

As I said, apple dev has always interested me so I have read a couple of books and completed numerous little projects.  

Right now I am working through the iOS Code School path and building and iOS client for the location broadcast server I spoke about in the Elixir section above.

I wouldn't mind working on iOS again... which leads me into...

### Swift 1.0

XCode 6.0.1 has been dropped and now I have Swift to play with :D. I didn't have my own Apple dev license so I had to wait.  I did pretty much read the iBook cover to cover in the interim.  

If I am to ever transition into this area, I would like to do so where I can hit the ground running so I might start to port the Objective-C location client to swift (or maybe just parts of it to get used to the interop).

### Data Structure & Algorithms 

I always try to keep a balance of new technologies/language and CS theory.   Right now I do have a desire to spend more time reading up on Data Structures and Algorithms and their application to big problems.  This is the stuff that you learn and is timeless, and there is plenty of it to get stuck into!

I was fortunate enough to do the ['Writing Concurrent Code with Lock-Free Algorithms' course](http://instil.co/courses/writing-concurrent-code-with-lock-free-algorithms/) by [Martin Thompson](http://mechanical-sympathy.blogspot.co.uk) and I got to hear him speak a couple of weeks ago at the End of Summer Bash event... if you haven't watched one of his talks please take the time to do so [(now)](http://www.infoq.com/author/Martin-Thompson). 

The big take away for me is the fastest, most elegant and performant solutions, come from  using the most appropriate, hand crafted, intelligently selected data structures and algorithms to solve the problem over picking up general purpose tools.  

There is so much more in this area that I want to talk about but not in this post... but definitely add [Mechanical Sympathy](http://mechanical-sympathy.blogspot.co.uk) to your blog reader.

### Functional & Reactive Programming

I completed the [Functional Programming Principles in Scala](https://www.coursera.org/course/progfun), a MOOC on Coursera.  Before that I completed the [Reactive Programming](https://www.coursera.org/course/reactive) course.  These were very good, humbling, challenging and rewarding.  

I have been using RX in .NET for years which helped a lot but I still found the Reactive course very worth while.  Both these courses use Scala and I enjoyed getting to learn it a bit better.  I liked how the reactive programming course built up concepts in layers, starting with getting the students to build a priority queue and finishing with reactive system using the [Akka](http://akka.io) actor model.

### Some Books: Remote, Rework & Lean Start-up

In the last 6 months I have read these books each twice (well I used audible so they were read to me twice). Wonderful books which resonated with me on so many levels.  They are informative and practical guides which are also quite inspiring.

I think I really got inspired to start developing outloud.io through my desire to just start something of my own from reading [The Lean Startup](http://theleanstartup.com).

### Teaching

As a senior engineer I teach as part of my job, but recently I have been helping my buddy who is learning to program.  

This is a different challenge altogether, starting from the basics and helping to set the mindset and guide the conceptual thinking required.

He has a degree and a load of music related qualifications and we discussed what would be the best way to start a career in software development.  

I have a degree in Computer Science, and I found it very useful, but not necessarily necessary... well depending on the desired job and in a sense that all that theory is accessible elsewhere.

He could go back a do a Masters degree in CS, but is the cost worth it? Maybe... but to get the most out of the year (or 2) having some programming experience would be required before hand and thats where I am helping out.

So, I got to thinking about what are good resources for becoming a programmer and basically ended up recommending the same resources that I use:

- Coursera & MOOCs
- Code School 
- Books
- Podcasts

He has also found some other reasons handy, so I will be sure to link them and his new blog when he gets round to setting it up!

### Meteor and DDP

I must say [meteor.js](https://www.meteor.com) and [Distributed Data Protocol](https://www.meteor.com/blog/2012/03/21/introducing-ddp) look very interesting indeed.  

Have watched a few [screencasts](https://www.meteor.com/screencast), something that is well and truly on the radar now.

### Whats next?

I really need to prioritize thats for sure. This is quite a lot I have going on.  It blew my mind when I put it all into Trello... just too much interesting stuff and not enough hours in the day.