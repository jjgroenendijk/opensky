---
type: Decision
title: Design metrics
description: The limits that keep types small, loosely coupled, acyclic, and minimally public,
  why each value was chosen, and how each rule lands from a report to a gate.
tags: [decision, architecture, lint, code-quality]
---

# Design metrics

These checks keep each type small and keep its links to other types few and visible. The
principles behind them give no fixed numbers, so each limit below is our own choice. This page
records each value and its reason.

## How a rule lands

Each rule starts at zero, as every check here does
([code-health automation](/decisions/code-health-automation.md)):

1. The rule lands as a report in `make design-report`. The report prints each finding and the
   count per module, and it fails nothing.
2. The findings are fixed per module, one module or a group of modules per pull request.
3. The limit moves into the lint config, and the rule becomes a gate, when the count on `main`
   is zero. There is no exception list.

## Rule 1: size limits

SwiftLint checks the size of a function's parameter list, a tuple, and nested types. The
report reads `tools/design/size.swiftlint.yml`, which holds the limits that are not a gate yet.
The nesting limit is a gate in `tools/lint/.swiftlint.yml` since 2026-11-09.

| Limit | Value | Before | Findings when set (2026-11-09) | Reason |
| --- | --- | --- | --- | --- |
| Parameters of a function, defaults not counted | 4 | 5 | 283 | A long list usually means a missing value type. A limit of 3 gives 1056 findings, so 4 comes first and 3 is tried when this count is zero |
| Members of a tuple | 2 | 2 | 0 | Already the lint value. A wider result gets a named struct |
| Levels of nested types | 1 | 2 | 17 | A type nested two levels deep is hard to find and to name from outside. Most findings are record layouts in `OpenSkyFormatsESM` |

Example: `func cast(spell: FormID, from caster: ReferenceKey, at target: ReferenceKey,
hand: SpellHand, cost: Float)` takes 5 parameters. A `SpellCast` value that holds them makes
the call read as one idea and gives the next field a home.
