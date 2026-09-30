---
type: Decision
title: Concurrency
description: Which subsystems run off the main actor, which isolation each one uses, and how
  finished work reaches the frame loop - with the measurements behind each choice.
tags: [decision, concurrency, main-actor, streaming, audio, scripting]
---

# Concurrency

Every package module uses `defaultIsolation(MainActor.self)`. So all code runs on the main actor
unless it says otherwise. This page decides which subsystems leave the main actor, what they use
instead, and how their results come back to the frame loop.

A subsystem leaves the main actor only when a measurement shows that its work does not fit in a
frame. At 30 frames per second a frame is 33.33 ms. Leaving the main actor has a cost: the data
that crosses must be `Sendable`, and the code must be written for two threads.

## Three kinds of isolation

- **Main actor.** The default. Game rules, coordinators, the renderer's encode, and the UI.
- **One serial worker with a `Mutex` mailbox.** Long synchronous work that owns caches with no
  locks inside. One serial queue runs the work. The queue owns the caches. Only values in a
  `Mutex` cross to the main actor. An actor is not used here, for the reasons in
  [cell streaming](/engine/cell-streaming.md): the work has no `await` inside, and an actor would
  add `await` to the synchronous frame loop.
- **`@concurrent` function.** One-shot work outside the frame loop, such as loading a list for a
  panel. The function takes `Sendable` values and returns a `Sendable` value. A main-actor `Task`
  awaits it.

No subsystem gets its own actor today. A future one needs a measurement and a change to this page.

## Decision per subsystem

The per-frame numbers come from `openskycli bench --fly-path` on a Debug build, 3026 frames at
1280x720 across 35 cells of Tamriel (measured 2026-09-30). Debug is slower than Release, so the
numbers are an upper bound.

| Subsystem | Isolation | Reason |
| --- | --- | --- |
| Cell streaming (grid, scheduling, scene swap) | Main actor | It decides what to build and swaps finished scenes into the renderer. Both are cheap and touch main-actor state |
| Cell builds | Serial worker, `Mutex` mailbox | Collision: average 81 ms, maximum 949 ms per cell. Actors: average 336 ms, 95th percentile 1532 ms. Many frames each |
| Asset decode (NIF, DDS, meshes, textures) | Inside the cell build worker | It runs as part of a cell build and fills the same caches |
| Distant LOD and door transitions | Inside the cell build worker | Same caches and same queue as cell builds |
| Audio decode | Serial worker, `Mutex` state | Decoders are not `Sendable`, and AVFAudio calls back on its own threads. See [audio](/engine/audio.md) |
| Audio tick (volumes, retire, purge) | Main actor | Average 0.006 ms, maximum 0.450 ms per frame |
| Script execution (Papyrus) | Main actor | Average 0.007 ms, maximum 0.465 ms per frame. Native functions read and write main-actor game state synchronously |
| Save and load | Main actor | Runs once per user action, not per frame. Not measured. The encoder and decoder are pure, so a move later is small |
| Launch setup (plugin load, record stores) | Main actor | Under 0.33 s from process start to the first frame. The heavy actor indexes are built lazily on the cell build worker |
| Preview catalog load and filter | `@concurrent` function | Hundreds of thousands of records. A panel waits for it, the frame loop does not |

The cell build worker hands its scenes over in a checked `Mutex`, because `CellScene` is
`Sendable`. It owns the builder alone: the main actor reads a separate set of record stores
([cell streaming](/engine/cell-streaming.md)).

The render encode grew with the loaded cells in the same run: 0.6 ms at the start and up to 24 ms
with 25 cells loaded. That is a data layout question for the per-frame profile, not a reason to
leave the main actor.

## How results reach the frame loop

A worker never calls into main-actor code. The main actor never waits for a worker.

1. **Main actor to worker: a request with values.** A cell build request carries a
   `WorldStateSnapshot` taken on the main actor. An audio start carries the file and the node. The
   main actor posts it and returns.
2. **Worker to mailbox.** The worker puts each finished result into its `Mutex` mailbox.
3. **Mailbox to main actor: one drain per frame.** The frame tick drains the mailbox at one fixed
   point, for example `drainCompleted()` in `CellStreamer`. The drain takes what is there and
   never waits. The streamer adds at most one finished cell per frame, so a burst of results
   spreads over several frames.

A framework callback on its own thread, such as an AVFAudio buffer completion, follows the same
rule. It sets a value behind a lock, and the main actor reads
it on the next tick. A callback that only sets one flag may instead hop with
`Task { @MainActor in ... }`.

## Rules for new code

- Do not add `@unchecked Sendable`, `Task.detached`, `DispatchQueue.main`, or a semaphore.
- A new `DispatchQueue` needs a row in the table above. The two today are the cell build queue
  and the audio decode queue.
- Shared state off the main actor lives in a `Mutex`, so the compiler checks it.
- Data that crosses threads is a `nonisolated` `Sendable` value type.
