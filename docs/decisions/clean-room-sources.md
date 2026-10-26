---
type: Decision
title: Clean-room sources
description: Why OpenSky may learn facts and behaviour from SKSE, CommonLibSSE, and other
  community sources but never takes code or binary structure from them, and why tolerance of
  SKSE does not extend to an engine reimplementation.
tags: [decision, legal, clean-room, skse]
---

# Clean-room sources

OpenSky learns what the game does from any lawful source. It never takes code or structure
that came from the game binary. The `using-outside-sources` skill holds the tiers and the
workflow. This page holds the reasons.

Words used on this page:

- **Clean-room** means the people who write the new code never see the protected code. They
  work from a description of behaviour only.
- An **interop fact** is a value or behaviour visible outside the binary, such as a value a
  script function returns.
- **Binary structure** is what exists only inside `SkyrimSE.exe`: class layouts, offsets,
  function addresses, and class names from its RTTI (runtime type information).

## The law

EU Software Directive 2009/24/EC, article 6, and the Dutch Auteurswet allow decompiling a
program you lawfully own, to make another program work with it. The same article sets two
limits on the information gained:

- It may not be given to others, unless interoperability needs it.
- It may not be used to build a program substantially similar in its expression.

Copyright protects expression: code, and the structure and naming of that code. It does not
protect ideas, facts, or behaviour. "A negative perk point count gives 255" is a fact.

## Why SKSE internals stay out

SKSE's C++ source is a map of `SkyrimSE.exe`, made by disassembling it. OpenSky reimplements
the engine. If OpenSky's types copied the binary's layouts and class names, anyone could argue
that OpenSky contains decompiled Bethesda structure. That is the one argument a clean-room
reimplementation must not allow.

Two projects show both sides:

- OpenMW reimplements Morrowind's engine, clean-room, and has worked in public for more than
  15 years.
- re3 and reVC rebuilt GTA III and Vice City from decompiled code. Both needed the original
  game files. Take-Two had them taken down in 2021 and then sued the developers. Needing the
  original game did not protect them.

Bethesda tolerates SKSE. That is a business choice, not a licence, and it covers SKSE only.
SKSE runs inside Bethesda's engine and keeps it in use. OpenSky replaces that engine, so the
same tolerance cannot be assumed.

The internals would not help much either. OpenSky is a Swift engine with its own data model.
An offset into the game's actor class means nothing in it. SKSE support is planned at the
script level only. SKSE DLL plugins will never load.

## SKSE's own terms

SKSE64's source is published at <https://github.com/ianpatt/skse64>, but it is not open
source. Its readme forbids releasing a modified version and rehosting the files. It also
requires any plugin that includes SKSE source to publish its own source. Its licence file
bans the Skyrim Together team from using the files at all, for copyright infringement.

So OpenSky may read SKSE to learn behaviour, but may not copy its code. The `.psc` script
files are SKSE's script interface. OpenSky must match this interface for scripts to work.

## Why the clean-room read uses a sub-agent

The tiers allow facts from source code that was built on the binary, such as SKSE's C++ and
CommonLibSSE. The risk is that the code shape leaks into OpenSky code. So a read-only
sub-agent reads the source and returns prose, and the session that writes code sees only that
prose. The prose goes into `docs/` with its source cited, so a reviewer can check that no code
or structure passed through it. The project's general rule against sub-agents exists because
parallel agents edited the same worktree. A read-only sub-agent edits nothing, so it does not
have that problem.

Where possible, the reference game with SKSE installed confirms the behaviour. The observed
behaviour then becomes the real source, and the SKSE code only showed where to look.
