---
title: "Senior Software Engineer, Processing Platform"
org: "Alert Logic"
start: 2015-05-01
end: 2017-11-01
location: "Belfast"
tags: ["erlang", "otp", "security", "distributed-systems", "aws", "riak"]
highlights:
  - "Erlang engineer on the original Processing Platform: a distributed-Erlang cluster over Riak doing big-data packet and log processing for real-time exploit and vulnerability detection"
  - "Architected and developed its ground-up replacement from the lessons of the first: serverless Erlang on AWS, with a custom bootstrap that brought an Erlang VM up inside a Lambda function and kept it warm for thirty minutes, fed by Kinesis and SQS, so capacity scaled horizontally with the firehose"
  - "Mentored an intern through building a GraphQL-based incident-analysis platform"
cv:
  include: true
  weight: 80
  highlights:
    - "Architected the ground-up replacement of an Erlang security-processing cluster as serverless Erlang on AWS: BEAMs bootstrapped inside Lambda and kept warm, Kinesis and SQS queueing (2016–17)"
---

Two platforms, really. The first was the original cluster: distributed
Erlang over Riak, keeping up with a firehose of packets and logs and
finding the attacks in them. The second was its replacement, designed
from the ground up on what the first had taught us, and the fun part of
it was running Erlang where nobody expected it: a small library that
bootstrapped a BEAM inside a Lambda function and kept it warm for thirty
minutes, with Kinesis and SQS doing the queueing, so the platform scaled
out with the traffic rather than being sized for it. The security depth
I lean on a decade later starts here.
