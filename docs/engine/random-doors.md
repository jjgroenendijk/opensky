---
type: Subsystem
title: Random teleport doors
description: How a door with a destination list and no link finds a random matching door,
  links to it both ways, and where the player lands.
tags: [engine, doors, cells, travel]
---

# Random teleport doors

A random door has no fixed destination. The first time it is used, it finds a matching door in
one of its destination cells or worldspaces, links to it, and sends the player there.

OpenSky does not build this yet. It reads the destination list from the record, but nothing uses
it.

## Which doors are random

A door is a random door when its base `DOOR` record has a `TNAM` destination list. There is no
flag. The reference acts as a random door only while it has no `XTEL` teleport link.

## Finding a target door

1. The source location is the activating actor's worldspace, or its interior cell.
2. The door's destinations, cells or worldspaces, are tried in random order, each at most once.
3. In each candidate cell, or in a worldspace's persistent cell, the game collects doors that:
   - are random doors themselves;
   - list the source location among their destinations;
   - have no teleport link yet;
   - are not disabled or deleted.
4. One of them is picked at random.
5. The player remembers which destination index each door used last. That index is skipped in
   favour of another one, and the new index is stored.

When a door is found, the two doors are linked both ways, and the teleport goes ahead. When no
destination gives a door, the game's failure message shows, and the player stays.

```mermaid
flowchart TD
    A[Player activates a door] --> B{Base DOOR has TNAM<br/>and reference has no XTEL?}
    B -- no --> N[Normal door: use its link]
    B -- yes --> C[Shuffle the destinations,<br/>skip the one this door used last]
    C --> D{Destination left to try?}
    D -- no --> F[Show the failure message]
    D -- yes --> E[Collect random doors there that list the source,<br/>have no link, and are enabled]
    E --> G{Any door?}
    G -- no --> D
    G -- yes --> H[Pick one at random,<br/>store the destination index]
    H --> I[Link both doors both ways]
    I --> J[Teleport the player]
```

## Where the player lands

The player lands at the target door's random teleport marker (`XRTM`) when it has one. Otherwise
the player lands a fixed distance in front of the door, 150 units by default and more for an
automatic door, and faces away from it.
