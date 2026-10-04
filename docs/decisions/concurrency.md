---
type: Decision
title: Concurrency
description: Asset loading runs off the main actor and simulation stays on it - the isolation
  each subsystem uses, how loaded assets reach the frame loop, and the measurements behind it.
tags: [decision, concurrency, main-actor, streaming, audio, scripting, loading]
---

# Concurrency

Every package module uses `defaultIsolation(MainActor.self)`. So all code runs on the main actor
unless it says otherwise. This page splits the work into two kinds and gives each kind its own
default:

- **Loading** reads a file and decodes it: NIF, HKX, DDS, PEX, SWF, WAV, XWM, FUZ, and save
  files. Loading runs off the main actor by default.
- **Simulation** is the game rules, the coordinators, Papyrus, animation updates, and the render
  encode. Simulation runs on the main actor in a fixed order.

At 30 frames per second a frame is 33.33 ms. One read from an archive on an external disk, plus
a decode, can take a large part of that. A load that runs on the main actor the first time an
asset is needed makes a frame late, and the player sees a stutter (a hitch).

## Why loading is off the main actor by default

Large game engines, such as Unreal and Unity, load assets this way. The game thread asks for an
asset and gets a handle. A loader thread reads and decodes it. The game thread takes the
finished asset in a later frame. A synchronous load during gameplay counts as a bug there.

The old rule allowed a load on the main actor until a measurement showed a problem. A hitch from
a first-use load is rare and hard to measure, so such loads stayed on the main actor. The new
rule turns this around: a load stays on the main actor only with a written reason.

## Why simulation stays synchronous

Making the frame loop `async` would cause three problems:

- **Reentrancy.** Each `await` on the main actor lets other main-actor code run before the
  function goes on. Game state can change in the middle of an update. For example, an actor's
  health can change between the hit check and the damage step.
- **No fixed order.** Work that resumes after an `await` runs when the scheduler chooses. The same
  input then does not give the same result, so bugs do not repeat and tests become unreliable.
- **No gain.** The simulation is cheap. Papyrus takes 0.007 ms per frame on average and 0.465 ms
  at most. The audio tick takes 0.006 ms on average.

So no frame code uses `await`. Moving a simulation subsystem off the main actor still needs a
measurement.

## Three kinds of isolation

- **Main actor.** Simulation, the UI, and the drain of finished loads.
- **One serial worker with a `Mutex` mailbox.** Loading that runs during play, and long
  synchronous work that owns caches with no locks inside. One serial queue runs the work and owns
  the caches. Only values in a `Mutex` cross to the main actor. An actor is not used here, for the
  reasons in [cell streaming](/engine/cell-streaming.md): the work has no `await` inside, and an
  actor would add `await` to the synchronous frame loop.
- **`@concurrent` function.** One-shot loading outside the frame loop, such as a list for a panel
  or a save file. The function takes `Sendable` values and returns a `Sendable` value. A
  main-actor `Task` awaits it. The UI shows that the work is in progress.

No subsystem gets its own actor.

## How a loaded asset reaches the frame loop

A worker never calls into main-actor code. The main actor never waits for a worker.

1. **Request.** A coordinator on the main actor asks for an asset by path. The request carries
   only values, such as the path and a `WorldStateSnapshot`. The main actor posts the request and
   returns at once.
2. **Load.** The worker reads and decodes the file. It puts the result, or the error, into its
   `Mutex` mailbox. The result is a `nonisolated` `Sendable` value.
3. **Drain.** The frame tick drains the mailbox at one fixed point, for example
   `drainCompleted()` in `CellStreamer`. The drain takes what is there and never waits. So
   finished loads enter the simulation in a fixed place in the frame.

A framework callback on its own thread, such as an AVFAudio buffer completion, follows the same
rule. It sets a value behind a lock, and the main actor reads it on the next tick. A callback
that only sets one flag may instead hop with `Task { @MainActor in ... }`.

### Before the asset arrives

Every asynchronous load has a defined behavior for the frames before its result arrives. The
caller writes it down next to the request. Examples:

| Asset | Behavior until it arrives |
| --- | --- |
| Animation clip | The actor keeps its current pose or clip |
| Sound | The sound starts one or more frames late |
| Menu movie | The menu opens when the movie is ready |
| Papyrus script | The event waits in the queue of that script instance |

A failed load is remembered, so the next request for the same path does not read the file again.

### Prefetch

A need that is known early is loaded early. A cell build already knows its NPCs, its references,
and its records. The cell build worker can load their gait clips, scripts, and sounds together
with the cell. Then most first uses find the asset ready.

### Tests

The loader is a port. A unit test passes a loader that finishes each request at once, so the
asset is ready at the next drain. The test stays deterministic.

## Decision per subsystem

The per-frame numbers come from `openskycli bench --fly-path` on a Debug build, 3026 frames at
1280x720 across 35 cells of Tamriel (measured 2026-09-30). Debug is slower than Release, so the
numbers are an upper bound.

| Subsystem | Isolation | Reason |
| --- | --- | --- |
| Cell streaming (grid, scheduling, scene swap) | Main actor | Simulation. It decides what to build and swaps finished scenes into the renderer |
| Cell builds | Serial worker, `Mutex` mailbox | Collision: average 81 ms, maximum 949 ms per cell. Actors: average 336 ms, 95th percentile 1532 ms. Many frames each |
| Asset decode for cells (NIF, DDS, meshes, textures) | Inside the cell build worker | Loading. It fills the same caches as the cell build |
| Distant LOD and door transitions | Inside the cell build worker | Loading. Same caches and same queue as cell builds |
| Animation clips, behavior graphs, camera tracks | Serial worker, `Mutex` mailbox | Loading during play |
| Papyrus script files | Serial worker, `Mutex` mailbox | Loading during play |
| Audio file read and decode | Serial worker, `Mutex` state | Loading during play. Decoders are not `Sendable`, and AVFAudio calls back on its own threads. See [audio](/engine/audio.md) |
| Audio tick (volumes, retire, purge) | Main actor | Simulation. Average 0.006 ms, maximum 0.450 ms per frame |
| Script execution (Papyrus) | Main actor | Simulation. Native functions read and write main-actor game state synchronously |
| Menu movies (SWF) and fonts | Serial worker, `Mutex` mailbox | Loading when a menu opens |
| Save, load, and the save list | `@concurrent` function | Loading after a user action. The encoder and decoder are pure |
| Preview catalog and detail | `@concurrent` function | Loading for a panel. Hundreds of thousands of records |
| Launch setup (plugin load, record stores) | Main actor | Runs before the first frame. Under 0.33 s from process start to the first frame |

Some loads in this table still run on the main actor. Each one has a GitHub issue.

The cell build worker hands its scenes over in a checked `Mutex`, because `CellScene` is
`Sendable`. It owns the builder alone: the main actor reads a separate set of record stores
([cell streaming](/engine/cell-streaming.md)).

The render encode grew with the loaded cells in the same run: 0.6 ms at the start and up to 24 ms
with 25 cells loaded. That is a data layout question for the per-frame profile, not a reason to
leave the main actor.

## Rules for new code

- Do not read or decode a file on the main actor after the first frame. A load that must stay
  there needs a row in the table above with the reason.
- Do not use `await` in frame code. A loaded asset reaches the frame through a drain.
- Do not add `@unchecked Sendable`, `Task.detached`, `DispatchQueue.main`, or a semaphore.
- A new `DispatchQueue` needs a row in the table above. Prefer an existing worker over a new
  queue.
- Shared state off the main actor lives in a `Mutex`, so the compiler checks it.
- Data that crosses threads is a `nonisolated` `Sendable` value type.
