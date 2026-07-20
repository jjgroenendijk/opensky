---
type: Decision
title: Metal shader formatter + linter
description: clang-format (via Xcode) formats .metal; Metal compiler warnings-as-errors
  is the linter. Resolves the AGENTS.md every-language-tooling rule for Metal.
tags: [decision, tooling, metal, lint, format]
timestamp: 2026-07-20T00:00:00Z
---

# Metal shader formatter + linter

## Decision

- Formatter: clang-format (Metal is C++-based; Apple ships clang-format with Xcode,
  invoked `xcrun clang-format`). Config `tools/format/.clang-format`, style matched to
  hand-written `opensky/Shaders.metal` conventions. Wired into `make format` /
  `make format-check` (`metal-format` target) + pre-commit hook
  `.githooks/pre-commit/35-metal-format.sh` (format + re-stage, mirrors Swift hook).
- Linter: no standalone Metal linter exists (clang-tidy needs a Metal compile database;
  not worth the setup for one shader file). Documented exception: the Metal compiler is
  the linter — `MTL_TREAT_WARNINGS_AS_ERRORS = YES` in both build configs -> any shader
  warning fails `make build`, which the pre-push hook + CI run.

## Rationale

AGENTS.md requires linter + formatter per language. clang-format needs no new
dependency (Xcode already required). Alternatives rejected: clang-tidy (compile-db
setup cost, little signal for MSL), no-op exception (formatter is free, take it).

## Consequences

`.metal` churn on first format is one-time; formatter is authority from here. New
shader warnings block build — fix, never downgrade (AGENTS.md lint policy).
