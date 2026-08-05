---
type: Tool
title: Run output layout and make prune
description: Where a script's transcripts, captures, and result bundles go - one
  timestamped run directory per run with a latest symlink - and how make prune deletes
  stale worktree caches and aged-out run output without touching sources.
tags: [tool, make, logs, disk, retention]
timestamp: 2026-08-04T00:00:00Z
---

# Run output layout and make prune

Two gitignored trees hold everything a run of the tooling produces: `logs/` for
transcripts and captures, `build/test-results/` for `.xcresult` bundles. Both grow without
bound and neither is anybody's job to clean, which fills the data volume mid-session — one
`DerivedData/` per linked worktree already runs to tens of gigabytes, and the worktree for
a merged branch leaves its cache behind. The convention below makes each run a single
directory, and `make prune` deletes the runs and caches nothing needs any more
(issue #347).

## Contents

* The run directory convention
* Which scripts write where
* make prune
* What prune will not touch

## The run directory convention

Every script that writes output a human reads later allocates one directory per run:

```text
logs/<script>/<UTC timestamp>/          e.g. logs/probe/20260804T191739Z/
logs/<script>/latest -> <UTC timestamp>
build/test-results/<name>/<UTC timestamp>/<name>.xcresult
```

The timestamp is `date -u +%Y%m%dT%H%M%SZ`, so directory names sort in time order — that
is how "newest run" and "older than the retention age" are both decided, without consulting
modification times that a backup or a copy can rewrite. `tools/run-dir.sh` creates the
directory, repoints `latest`, and prints the absolute path:

```sh
run_dir="$("$root/tools/run-dir.sh" probe)"                       # under logs/
bundle="$("$root/tools/run-dir.sh" -b build/test-results unit)"   # under build/
```

Two rules follow from this and matter when adding a script:

* **Print the run directory.** A PR body links the run directory, not a loose file, so the
  whole evidence of one run travels together. Captures embed the user's game assets and
  stay gitignored (AGENTS.md "Legal and IP boundary"); the link is a local path.
* **A script that calls another script exports `OPENSKY_RUN_DIR`.** `tools/xcodebuild-run.sh`
  writes into that directory instead of opening its own, so `make realtest` keeps its
  build transcript, its test transcript, and its selector enumeration in one place. A
  wrapper that does not export it gets a separate run directory per inner script, which is
  the thing this convention exists to avoid.

Collisions inside the same second get a `-1`, `-2` suffix rather than sharing a directory.

## Which scripts write where

| Producer | Run directory | Contents |
| --- | --- | --- |
| `make build`, `cli`, `test`, `test-one`, `install` | `logs/<target>/` | xcodebuild transcript |
| `make test`, `make test-one` | `build/test-results/unit`, `.../one` | `.xcresult` bundle |
| `tools/test-ui.sh` | `logs/test-ui/`, `build/test-results/test-ui/` | transcript, `.xcresult` |
| `tools/realtest.sh` | `logs/realtest/`, `build/test-results/realtest/` | two transcripts, `enumeration.json`, `.xcresult` |
| `tools/probe.sh` | `logs/probe/` | `probe.log` and every PNG the probe renders |
| `tools/check-docs-links.sh` | `logs/docs-links/` | link report |
| `tools/vendor-ffmpeg.sh` | `logs/vendor-ffmpeg/` | configure and build log, only when it actually builds |

`make test-report` reads the newest `.xcresult` under `build/test-results`, one run
directory deep, and falls back to the DerivedData glob when there is none.

## make prune

```sh
make prune                    # retention 14 days
make prune DRY_RUN=1          # print the plan, delete nothing
make prune PRUNE_DAYS=2       # tighter retention
```

`tools/prune.sh` builds a plan, prints every entry with its size and the reason it is in
the plan, deletes them, and reports the space freed. Four rules produce the plan:

1. **Stale worktree caches.** Every directory under the main checkout's
   `.claude/worktrees/` that `git worktree list --porcelain` no longer names loses its
   `DerivedData/`, `build/`, and `logs/`. This is the rule that frees gigabytes: removing a
   worktree often leaves the directory behind precisely because those trees are untracked,
   so git's own `worktree prune` never reaches them.
2. **`build/install`**, the private Release tree `make install` used before it started
   sharing the main derived-data cache.
3. **Aged-out runs** under `logs/` and `build/test-results/`: a run directory whose
   timestamp is older than the retention age goes, except that the newest run of each
   script is always kept, so `latest` still resolves after a prune. A `latest` symlink left
   dangling by a prune is removed.
4. **Pre-convention leftovers**: loose files directly under `logs/` older than the
   retention age, and `.xcresult` bundles written straight into `build/test-results`.

## What prune will not touch

The plan is built from that fixed set of path shapes and nothing else — there is no
"delete everything untracked" rule, and no rule reaches a source directory. Every entry is
checked before deletion to sit inside this checkout or the worktree home, and the checkout
roots themselves are refused outright; a path that fails the check aborts the run instead
of being deleted. Sources, `Config/Local.xcconfig`, and the shared `.vendor/ffmpeg` prefix
(`make vendor-prune` handles per-worktree copies of that one) are out of scope.

`make clean` remains the way to empty the current checkout: it deletes this checkout's
`build/` and `DerivedData/` outright, retention age irrelevant. `prune` is for what no
checkout owns any more.
