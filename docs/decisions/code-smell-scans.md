---
type: Decision
title: Code-smell scans - duplication and dead code
description: jscpd gates new copy-pasted Swift and Periphery gates new unused code, both
  against a checked-in baseline; why these two tools and not SonarQube, SonarCloud, or
  swiftlint analyze.
tags: [decision, tooling, lint, code-quality]
---

# Code-smell scans - duplication and dead code

## Decision

SwiftLint already enforces size and complexity smells: function and file length,
cyclomatic complexity, nesting, and force-unwrap/try/cast. Two smells need tools that
see the whole program instead of one file at a time. They are gated locally:

- **Duplication: jscpd.** `make dup-check`, part of `make lint`, and the pre-commit
  hook `.githooks/pre-commit/47-duplicates.sh`. The thresholds are in
  `tools/lint/.jscpd.json`: a clone counts at 100 tokens and 10 lines, exact matches
  only. The scan covers every Swift directory in about half a second. On a failure the
  wrapper `tools/lint/duplicates.sh` prints only the new clones, with both locations.
- **Dead code: Periphery.** `make dead-code`, run on demand.
  It reports unused declarations, properties that are assigned but never read, unused
  imports, and redundant conformances. Periphery reads the index store the compiler
  writes during a build (`COMPILER_INDEX_STORE_ENABLE = YES` in
  `Config/Debug.xcconfig`), so it needs builds of the current tree for `openskyTests`,
  the app with `openskyRealDataTests`, and `openskycli`. `make dead-code` runs those
  builds itself, with the compilation cache off and into its own tree
  (`DerivedData-index/`), because a build replayed from the shared cache writes almost
  no index data. The first run in a worktree is a full build; later runs are
  incremental, and the scan itself takes about eight seconds. It is not in the pre-push
  hook, because the shared cache makes the ordinary builds unusable for it.
  The settings are in `tools/lint/.periphery.yml`.

Both gates compare against a baseline of the findings that were already there when the
gates landed: `tools/lint/jscpd-baseline.json` (content fingerprints) and
`tools/lint/periphery-baseline.json` (declaration USRs). New code must not add to the
baseline. The existing findings are tracked in GitHub issues, not in this wiki.
After a cleanup removes findings, `make dup-baseline` or `make dead-code-baseline`
shrinks the baseline. Regenerating it to hide a new finding defeats the gate.

A finding that is deliberate, such as a decoded record field that the format page
documents but nothing reads yet, is marked in place with
`// periphery:ignore - <reason>`. That follows the same rule as any other inline
suppression: give a specific reason.

## Rationale

The repository enforces machine-checkable rules through git hooks, and both local hooks
and CI must fail on a violation. A scan whose result lives only on a dashboard cannot do
that.

- **SonarQube and SonarCloud.** Sonar's quality gate is evaluated server-side and
  cannot block a commit. The self-hosted Community Build does not analyse Swift, which
  needs a paid edition. SonarCloud is free for this public repository, but it is driven
  from CI, which is suspended ([environment](/tools/environment.md)). It also has no
  Metal analyser. Rejected as a gate. It can still be added later as an advisory
  dashboard.
- **`swiftlint analyze` with `unused_import` and `unused_declaration`.** It needs the
  compiler log of a clean build, which costs minutes per run. Periphery covers the same
  two rules and more from the incremental index store. Rejected as redundant.
- **PMD CPD instead of jscpd.** CPD needs a Java runtime. jscpd is a single Homebrew
  binary and has baseline support built in. Chose jscpd.

Both tools are MIT licensed command-line tools, installed by `make bootstrap` through
Homebrew. Neither is linked into or shipped with OpenSky.

## Consequences

- The baselines are generated files. A merge conflict in one is resolved by rerunning
  the matching `*-baseline` target on the merged tree, not by hand.
- Periphery's results are only as fresh as the index store. After switching branches
  in the same worktree, stale records can hide or invent findings until the next build.
  `make clean` resets the index.
- `openskyUITests` is not built by `make dead-code`, so its sources are not scanned
  for dead code. They drive the app through accessibility identifiers and reference no
  engine declarations.
- Metal shaders are outside both scans. jscpd has no Metal grammar, and the project has
  one shader file.
