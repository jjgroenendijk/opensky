---
type: Decision
title: Python tools as one uv project
description: Repository tools that outgrow a shell script are Python in a uv project, linted
  and formatted by ruff, with pandoc as an external binary.
tags: [decision, tooling, dependency, python]
---

# Python tools as one uv project

Most tools are POSIX shell scripts. The [offline Creation Kit wiki](/tools/ck-wiki.md) sync does
HTTP with retries, JSON, parallel work, and HTML rewriting. That is too much for shell, and it
does not belong in the Swift engine or `openskycli`, because it never touches game data.

## Decision

- Such a tool is Python in a [uv](https://docs.astral.sh/uv/) project, starting with
  `tools/ck-wiki/`. The tool code uses only the standard library.
- `uv.lock` pins [ruff](https://docs.astral.sh/ruff/) (MIT), which formats and lints with every
  rule on. CI installs only uv, so local runs and CI use the same ruff without a separate pin.
- `make py-format`, `make py-format-check`, and `make py-lint` run it. They are part of `make fix`
  and `make check`, and CI runs the checks in the Static checks job.
- The tools have no unit tests. They do not ship in the app. Their output is checked by running
  them and reading the result; a sync reports every page that failed.
- The ruff configuration lives in the project's `pyproject.toml`, next to the code it checks. Its
  few ignored rules each carry a reason there.
- [pandoc](https://pandoc.org) (GPL-2.0-or-later) converts HTML to Markdown. It runs as a separate
  program and is never linked or shipped, so its licence does not reach our code. `make bootstrap`
  installs it with Homebrew.

## Alternatives

- A Python HTML-to-Markdown package such as `markdownify`. It would add a runtime dependency to
  a tool that otherwise needs none. pandoc is a mature converter and one Homebrew install.
- A global ruff from Homebrew. It drifts from the CI version; the lock file does not.
