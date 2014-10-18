---
layout: post
title: "Cracking the WIP"
date: 2014-10-07 22:47:36 +0100
comments: true
categories: 
published: false
---

I am not trying to write an essay here, just sharing a short story about why imposing WIP limits can be a very powerful tool for software teams.

- when WIP limit hit, it encourages:
  - team conversations
  - pair programming opportunity
  - time to perform code reviews

- An interrogation of User Stories in flight
  - Question why the WIP has been hit, what part of the production line is failing?
  - A chance to keep update the metrics
  - estimates tweaked based on new knowledge gained

- Prevents blockages caused by too much work in flight
  - User Story owner forced to push for progress on items holding up their user stories be it Code Reviews or whatever.
  - limits pressure on QA when too many items in flight each requiring test cases, maybe scripts, individual deployments and eventual verification

### A Retrospective..

At our last retrospective my team spoke about the fact that at one point in the previous 2 week sprint we had 7 user stories in "In Progress".

Some of these were in development, and some were pending code review, some were being verified by QA.  A whole lot goes on in our In Progress column, _and at this time we cannot do much about that_, so we look at what we can do.

### Limiting Work In Progress 

The make-up of the team is 3 Devs and a QA who split his time between 2 projects.  So, we imposed a WIP limit of 5 for the In Progress.  

Why? To ensure the developers were taking time to think about what was in flight before pulling more work.  

_WIP is Work In Progress_ and is a way of limiting how much work is in flight at any given time.  Since we operate on a trimmed down kanban board with only TODO, IN PROGRESS, REVIEW, DONE where IN PROGRESS is where the action happens we placed the limit there.

### So the Sprint Begins

The sprint starts, we all pull a user story.

#### 3 In Progress: 3 In Development

After a day one of the devs gets blocked, and needs some architect input to proceed.  A Blocker is placed on the User Story and another User Story is pulled.


#### 4 In Progress: 3 In Development, 1 Blocked

In the meantime, developer is working away on a medium sized story, all is well in his world.

I finish implementing my first user story, create a Code Review and pull in another User Story. 


#### 5 In Progress: 3 In Development, 1 Code Review, 1 Blocked

The Architect shares the knowledge required to UNBLOCK the first User Story. Code Review still pending and new User Story is being developed.

#### 5 In Progress: 1 Code Review.

I then complete the second user story, create the Code Review and TRY to pull the next item. BUT I CAN'T as we have hit the WIP LIMIT!!

### Feeling the Pain

I am then forced to take a good look at the board to see what is in flight (This is a good thing).

2 Code Reviews - They are my own so I cannot complete them, but I can sure as hell poke people to hurry up so my stories can progress to verification and out of IN PROGRESS to be reviewed by stake holder.

- Action was taken to move my User Stories along. (This is a good thing).

I then look to see where my teammates are.  I see 3 other User Stories in progress, yet only 2 developers, so something stands out.  The original User Story which became blocked is no unblocked.  I proceed to have a conversation with the developer who started this work, he informs me that he is working on something else and will back to it when he is done.

We have options, but the first that came to mind was that I could start working on it.  The other developer assures me he will jump on it again soon and it would take more time to bring me up to speed with it. So there is an inherrent cost to doing that...

But the best option was to park it, and allow me to pull something else.  

### An Updated View of Progress

We log against each user story based on an estimate associated with each sub-task and the burn down chart looked great, regardless of the Blocked User Story, time was being logged, code was being written and all was good.  Then we hit the WIP limit and it felt like that momentum was stalled.

Based on the fact I was asking questions about the stalled User Story and the fact that the user Story became unblocked with new information obtained meant that the estimate was re-evaluated there and then meaning we had a more up-to-date and realistic view of where we were with regards to completing the Sprint.

The estimate was large, there was much more work that originally expected and as such we were not so cocky as to our progress.

Again, none of the above would have happened unless these conversations were had, and the conversations would not have been had if I was able to pull the 6th User Story in.  We could better communicate the status of the feature to the stakeholder.

### Help Others

As this would free up the first developer to perform my 2 pending code reviews, and allow me to pull my 3rd and final user story which was the final part of an EPIC.

This could just as easily have been an opportunity for a developer to jump the fence and become a QA for a task, if our QA was at capacity. 

### Limited Waste

The goal here is to avoid WASTE, specifically any partially completed work can be categorized as waste simply because time and money has went into it and it is not achieving its potential by being released, so it is our job to ensure we complete it and have it ready for release asap.

This area goes deeper into topics such as deploying regularly, factoring your user stories and work items well so shippable milestones can be achieved frequently but I wont get into that now.

### Optimized the Flow

Yes, the first User Story took the hit for being Blocked, but also it could be argued unexpected / insufficient information which caused the blocker was it real enemy, that aside... the information was obtained an estimate was updated.

2 of my User Stories for were more likely to obtain code review.  This is a WIN, as these would be ready for QA sooner than they otherwise might have been.

### In summary

By not being able to pull the 6th User Story in, so many positives came out of me not being able to write more code, which in turn would stop the overall velocity of the User Stories within the Sprint.



