---
type: Decision
title: swift-collections for heaps and ring queues
description: Why the engine takes Apple's swift-collections as its first SwiftPM dependency, which
  of its modules it uses, where, and which queues stay plain arrays after measurement.
tags: [decision, dependency, swiftpm, navigation, scripting, streaming]
---

# swift-collections for heaps and ring queues

## Decision

- The package depends on [swift-collections](https://github.com/apple/swift-collections) from
  Apple. Its license is Apache 2.0, which allows redistributing OpenSky's code with it.
- Modules depend on the smallest product they need, `HeapModule` or `DequeModule`, never on the
  umbrella `Collections` product. A product is declared in `Package.swift` next to the local
  modules. `tools/lint/module-graph.sh` treats it as a module below every layer.
- The tracked `Package.resolved` pins the version, and Renovate proposes updates.

## Where it is used

- The A* open list of the navigation pathfinder is a `Heap`. The pathfinder had its own sift-up
  and sift-down code. The open entries have a strict total order (cost, then heuristic, then
  triangle), so any correct heap pops the same entries in the same order: paths and expansion
  counts do not change.
- The Papyrus runtime's recent-event list keeps the newest few entries and drops the oldest. It is
  a `Deque`, which says that intent and drops from the front in constant time.
- The Papyrus native dispatch's queued results and its call record are first-in, first-out. They
  are `Deque`s for the same reason.

## Queues that stay arrays

The cell streamer's load requests, rebuild requests, and pending build results stay arrays.
`Array.removeFirst()` moves every remaining element, but these queues are short: the default grid
is 5 x 5 cells, so a queue holds at most 25 cells, and the streamer takes at most one build per
frame. Measured with optimized code at 25 cells and at 225 cells (a 15 x 15 grid),
`Array.removeFirst()` costs tens of nanoseconds per pop. A frame lasts millions of nanoseconds,
so a `Deque` would only add churn to the streamer.

## Alternatives

- Keep the hand-written heap. It works, but it is code the project owns, tests, and reviews,
  for a data structure the standard ecosystem already maintains.
- A ring buffer of our own. Same objection, and `Deque` already exists, tested, from Apple.
