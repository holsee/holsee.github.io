---
layout: post
title: "Elixir, BEAM and OTP"
date: 2014-12-29 14:25:42 +0000
comments: true
categories: elixir otp
---

_As I plan to write and speak about Elixir on my blog and hopefully at some meet-ups soon, I though I would write a short post with handy descriptions of some of the key aspects that I can reference in one place..._

### What is Elixir?

Think Dave Thomas describes it best...

"The Elixir Programming Language wraps functional programming with immutable state and an actor-based approach to concurrency in a tidy modern syntax.  And it runs on the industrial-strength, high-performance, distributed Erlang VM."

It has very powerful meta-programming capabilities through compile time expansion of macros and the dynamic power of the language.  A good example of the developer productivity that can be gained is their use in the [routing system in the phoenix web framework](http://www.phoenixframework.org/v0.7.2/docs/routing). When learning about Elixir macros I found the '[Understanding Elixir Macros Series](http://www.theerlangelist.com/2014/06/understanding-elixir-macros-part-1.html)' by [Saša Jurić](https://twitter.com/sasajuric) to be very useful.

### What is the Erlang VM & BEAM?

The "Erlang VM" is the name of the virtual machine where all Erlang code is executed. Every compiled Erlang file has the suffix .beam. 

There is also an implementation of Erlang which runs on the JVM, called [Erjang](https://github.com/krestenkrab/erjang/wiki), but I guess the less said about that the better as the Erlang VM is really the awesome part if you ask me.

When you compile Elixir code it is converted to .beam format, which allows it to be executed on the Erlang VM.

### What is OTP?

OTP is set of Erlang libraries and design principles providing middle-ware to develop these systems. It includes its own distributed database, applications to interface towards other languages, debugging and release handling tools.

The OTP libraries (and the associated best practices to an extent) are mature, battle hardened and hide much of the boilerplate code required to perform common patterns such as creating a server to store state, recover from failures through supervision trees and so much more.

I look forward to writing about this with examples in future as I learn more about OTP myself.

_Where is OTP used?_

[egitsd](https://github.com/mojombo/egitd) - egitd is an Erlang git-daemon implementation that provides a more flexible,
scalable, and loggable way to serve public git repositories.  It is used by github.com.

[RabbitMQ](http://www.rabbitmq.com) - An open source message broker (sometimes called message-oriented middleware) that implements the Advanced Message Queuing Protocol (AMQP).

[More Projects using OTP...](https://github.com/erlang/otp/wiki/Projects-using-erlang-otp)


### Sources:

- [Erlang Website](http://www.erlang.org/doc/)
- [Erlang OTP Source on Github](https://github.com/erlang/otp/wiki)
- [Elixir Website](http://elixir-lang.org)
- [Programming Elixir Book](https://pragprog.com/book/elixir/programming-elixir) by [Dave Thomas](https://twitter.com/pragdave)
- [Elixir Sips Screencasts](http://elixirsips.com) by [Josh Adams](https://plus.google.com/+JoshAdams)
