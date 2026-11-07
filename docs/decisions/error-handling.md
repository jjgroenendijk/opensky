---
type: Decision
title: Error handling
description: Package modules never swallow an error, and the modules that read game files or
  saves never trap. The allowed calls for `try?`, the logging helper, and how the check works.
tags: [decision, swift, errors, lint, code-quality]
---

# Error handling

OpenSky fails loud on bad or missing data. Two rules hold, and `make error-handling` (in
`make check` and CI) checks both over every tracked Swift file under `Sources/`.

| Rule | Where | What fails the check |
| --- | --- | --- |
| No swallowed errors | Every package module. The app and `openskycli` are not package modules. | `try?`, except on an allowed call. A catch-all `catch` whose body is empty or only `return`, `return nil`, `continue`, or `break`. |
| No traps on file input | `OpenSkyFormats*`, `OpenSkyGameData`, `OpenSkySave` | `fatalError`, `precondition`, `preconditionFailure`, `assert`, `assertionFailure` |

## What to write instead

- A failure the caller cannot handle throws a typed error. A parser throws its format's error,
  such as `BinaryReaderError`, and a test feeds it the malformed bytes.
- A failure the game survives goes through `attempt { try call() }`. `attempt` runs the call. On
  failure it logs the error with the file and line as a warning in the `RecoveredFailure`
  category, and returns `nil`. So the code reads like `try?`, and the run's log shows each
  failure. Read the lines with
  `log show --last 10m --predicate 'category == "RecoveredFailure"'`.
- `attempt` has an overload for a call that returns an optional, so the result is `T?`, as with
  `try?`. An `async` call works the same: `await attempt { try await call() }`.
- In an `if`, `guard`, or `while` condition, write `attempt({ try call() })`, because Swift
  does not allow a trailing closure there.
- `attempt` takes a closure, not an `@autoclosure`. Swift counts a `try` inside an autoclosure
  argument as a `try` of the closure around the call, so `compactMap { attempt(try x) }` would
  be a throwing closure.
- A read of a file or folder that may not exist uses `attemptIfPresent`: a cache entry, a folder
  listing, or a file's attributes. A missing file gives `nil` without a log line, so a cache miss
  or an absent optional folder is not reported as a failure. Any other failure is logged.
- A lookup that asks "is this one of those?" uses a call that returns an optional, not a throwing
  call whose error is the normal answer. Such a probe would fill the log with expected failures.
- A value that may have one of several types, such as a JSON value, is decoded with
  `decodeIfType` on a `SingleValueDecodingContainer`. It returns `nil` on a type mismatch only,
  and throws any other error.
- A catch that handles one known error, such as `catch DDSError.unsupported`, is fine. The rule
  only reads catch-all blocks.

## Allowed calls

The rule names calls, not files. A `try?` is allowed when the last name of the call is on this
list. Each failure is expected and leaves nothing wrong behind.

| Call | Why its failure is harmless |
| --- | --- |
| `removeItem` | Cleanup of a temporary or stale file. The goal is that the file is gone. A failure means it was gone already, and a file left behind is overwritten or removed on the next run. |
| `close` | Closing a file handle after reading. The data is read already, and the handle is freed when its object goes away. |

Adding a call to the list is a design change of the rule. It needs the reason in this table.

## Traps in the file-reading modules

A trap turns a malformed file into a crash, so these modules have none. Two former traps
guarded programmer mistakes, not file input, and now behave like this:

- A `FourCC` code literal of the wrong length, such as `"ABC"`, gives `FourCC.invalidLiteral`,
  four zero bytes. No record or field signature has that value, so the code never matches, and
  a test of the switch shows the mistake.
- A second step for one `FrameSchedule` phase is a wiring mistake. It is logged as a fault, so
  it shows in the agent event stream, and the second step is dropped.

## The self-check

The script first runs both rules on small synthetic snippets. Each violation must fail, and each
clean snippet must pass, for example a `try?` inside a comment or a string. A rule that stops
matching fails the check before it reads the tree.
