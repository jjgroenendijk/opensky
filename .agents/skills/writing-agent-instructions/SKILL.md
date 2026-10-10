---
name: writing-agent-instructions
description: Writes and improves the instructions agents read in OpenSky - AGENTS.md files,
  skills, and memory - covering where a new rule belongs, how to phrase it, skill format
  limits, progressive disclosure, and evals. Use when adding, editing, moving, or reviewing
  an AGENTS.md, CLAUDE.md, skill, or memory, when the user corrects the agent or states a
  new rule to follow, or when a mistake repeats and a rule could prevent it.
---

# Writing agent instructions

Every line an agent reads at startup competes with the task for attention. The goal is
the smallest set of instructions that still prevents the mistakes agents really make.

Sources: Anthropic, "The new rules of context engineering for Claude 5 generation models"
(claude.dev blog) and "Skill authoring best practices"
(<https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices>).

## Where a new rule goes

Pick the first place that fits. Check that the rule is not already written somewhere
(`grep -rn` over `AGENTS.md`, `*/AGENTS.md`, `.agents/skills/`, `docs/`) and update that
copy instead of adding a second one.

1. **A lint rule or `make` target**, when a machine can check it. A check cannot be
   forgotten; prose can. Mirror a new gate in `ci.yml` (root `AGENTS.md`, Code quality).
2. **A better name, type, or signature**, when the code can make the wrong use hard.
3. **A nested `AGENTS.md`**, when the rule applies only in one folder, such as `Sources/`
   or `Tests/`. It loads only when an agent works there. It needs a `CLAUDE.md` symlink
   beside it; `make lint` checks this.
4. **A skill**, when the rule applies only to one kind of task. Extend the matching skill;
   add a new one only for a task no skill covers.
5. **The root `AGENTS.md`**, only when it applies to nearly every task. Prefer gotchas:
   facts about this repo that an agent would get wrong without being told.
6. **`docs/`**, when it explains a design, a format, or a tool rather than giving an
   instruction (`writing-wiki-docs` skill).
7. **`docs/tools/environment.md`**, when it is a fact about this machine or the outside
   world that will expire. Add the date observed.
8. **Memory**, when it is a preference of the user or project state that the repo should
   not record. Never copy into memory what the repo already says.

## How to write a rule

- Give the reason with the rule. A model that knows why can handle the case the rule did
  not foresee. "Build in a background shell, because a build can pass the tool timeout"
  beats "ALWAYS build in the background".
- Prefer judgment to fixed limits where the right answer depends on context. "Match the
  comment density of the surrounding code" beats "one comment line maximum".
- Keep capital letters (NEVER, MUST) for the few rules where a mistake is costly and cannot
  be undone. In this repo that is the legal section. Overuse makes every rule look equal.
- Point at a real file to copy instead of describing a pattern in prose. A file stays
  correct as the code changes; a description drifts.
- Do not explain what the model already knows. Ask of each paragraph: would an agent get
  this wrong without it?
- Use one term for one thing throughout a file.
- No dates or "after version X" in instructions; git records history. Expiring facts go
  in `docs/tools/environment.md`.
- Follow the writing style in the root `AGENTS.md`.

## Skill format

`make lint` checks the hard limits:

- Folder name equals the `name` field: lowercase, hyphens, a gerund such as
  `testing-and-verifying`. Never the words `anthropic` or `claude`.
- `description` at most 1024 characters, third person, and it says both what the skill does
  and when to load it, with the words a user or task would use. Agents choose a skill from
  the description alone, so a vague one never loads.
- `SKILL.md` at most 500 lines. Keep it well under.
- `evals.json` with at least three scenarios.

Structure:

- Put the decisions and the workflow in `SKILL.md`. Move long reference material into a
  file beside it and link it from `SKILL.md`. Links go one level deep: a reference file
  does not send the agent to a third file, because agents often read nested files only in
  part.
- A reference file over 100 lines starts with a short list of its sections.
- Match freedom to risk. Give exact commands for fragile steps, such as the real-data
  runs; give goals and heuristics where many approaches work.
- A multi-step workflow gets numbered steps and, where quality matters, a check-fix-repeat
  loop, such as `make fix`, then fix what it reports, then run it again.
- Add the skill to the table in the root `AGENTS.md`.

## Evals

Each skill folder has `evals.json`, a list of scenarios:

```json
{
  "skills": ["testing-and-verifying"],
  "query": "make test-unit failed. What broke?",
  "files": [],
  "expected_behavior": ["Runs make test-report instead of hand-parsing .xcresult JSON"]
}
```

An empty `skills` list means the skill must not load for that query. Write the scenarios
before or with the skill, from mistakes agents really made. After changing a skill, run
its scenarios in a fresh session and compare the behavior with `expected_behavior`. When
an agent ignores a rule, find out why before adding words: the rule may be hard to find,
in the wrong file, or missing its reason.

## Review an instruction file

1. Measure it: `wc -l AGENTS.md */AGENTS.md .agents/skills/*/SKILL.md`.
2. For each section, ask: does it apply to nearly every task? If not, move it by the list
   in "Where a new rule goes".
3. Remove text that repeats code, `docs/`, another file, or a check that already enforces
   it.
4. Check that every path, symbol, and command named still exists.
5. Run `make check`.
