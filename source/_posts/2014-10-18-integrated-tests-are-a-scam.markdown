---
layout: post
title: "Integrated Tests Are A Scam"
date: 2014-10-18 23:04:51 +0100
comments: true
categories: testing
---

Found this gem in a tweet from [@david_whitney](https://twitter.com/david_whitney), and as he says the title is trolly but none the less is an excellent talk on automated testing. 

{% vimeo 80533536 %}

### Integrations Tests Lead to Bad Design

- An interesting point is made (and I am paraphrasing) that the more integration tests we have the less design feedback we get, leading to sloppy design as we don't feel the same feedback & design pressure...

### What Failed and Where?

- Integration tests may highlight failures, and the name of the test may go a long way to saying what failed, but pin pointing the actual location and reason for the failure is often lost in the generalization of the test itself.

### The Systemic Growth of Integration Tests

"...[they're] like taking aspirin that make your headache worse..."

- Given 3 components which each interact with each other, how many tests would we need to cover all code paths?

| Component  | # Paths  |
|------------|----------|
|     A      |     3    
|     B      |     5    
|     C      |     7    

3 x 5 x 7 = 105 Integration Tests* 


- Add a 4th subsystem, as a result of a refactoring, with 2 paths removed from C moved into Component D:

| Component  | # Paths  
|------------|----------
|     A      |     3    
|     B      |     5    
|     C      |     5    
|     D      |     2    

3 x 5 x 5 x 2 = 150 Integration Tests*

*At Least as to cover all code paths.

- This is an example of *negative design pressure*, specifically in this instance to refactoring, which itself is important to obtaining good design. 
- Resulting in another 45 tests being created and a on going cost of the time it will take to execute these tests.
- Not to mention the time it takes to run these tests hardly lends itself to a rapid Red Green Refactor cycle that would be possible with more isolated tests.


### The Solution

- Design to Contracts
-- If each Component operates against a contract, and the interactions between each component are clearly identified through design then come implementation we will be able isolate and ensure each component behaves correctly given the contract is upheld on both ends.

- Tests Subsystems in isolation
-- Isolation can be achieved through the use of Test Doubles or Mocks, to ensure each interaction with other components follow the contract under each of the specified scenarios.


_The talk goes into much more detail and is crammed with practical advice... GO WATCH and make the world a better place._
