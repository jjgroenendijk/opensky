---
name: consulting-creation-kit-wiki
description: Looks up the Creation Kit wiki (ck.uesp.net) in the local Markdown mirror - Papyrus
  scripts, functions, and events, condition functions, forms and record fields, editor tabs, and
  game settings - and syncs the mirror with make ck-wiki. Use whenever a task needs the CK wiki or
  ck.uesp.net, such as checking a Papyrus signature, an event's parameters, a condition function,
  or how the editor sets a field, instead of fetching the wiki or the Wayback Machine.
---

# Consulting the Creation Kit wiki

The wiki is mirrored as Markdown in `.cache/ck-wiki/` of the main checkout, which every worktree
shares. Read pages there. Do not fetch `ck.uesp.net` pages: the site answers scripts with HTTP 403
(`docs/tools/environment.md`), and the mirror already holds every English page.

## Find the mirror

```sh
wiki="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.cache/ck-wiki"
ls "$wiki/index.md"
```

If `index.md` is missing, or the task needs an edit made to the wiki in the last few days, sync
first:

```sh
make ck-wiki
```

Run it in a background shell. The first run fetches about 2,800 pages and takes most of an hour;
a later run fetches only changed pages and takes a minute. It needs `uv` and `pandoc`, which
`make bootstrap` installs. When the API is blocked, it falls back to the Wayback Machine by
itself; do not fetch the archive by hand.

## Find a page

The file name is the page title. Common title patterns:

| Looking for | File |
| --- | --- |
| A Papyrus function or event | `GetActorValue - Actor.md`, `OnHit - ObjectReference.md` |
| A Papyrus script object | `Actor Script.md`, `ObjectReference Script.md` |
| A condition function | `GetIsID.md`, `GetActorValue.md` (no script suffix) |
| A form type or editor window | `Actor.md`, `AI Data Tab.md` |
| Everything in a category | `Category/Condition Functions.md` lists its member pages |

When the exact title is unknown, search. File names first, then text:

```sh
find "$wiki" -name '*.md' -not -path '*/.sync/*' | grep -i 'actorvalue'
grep -rli --include='*.md' --exclude-dir=.sync 'OnMagicEffectApply' "$wiki"
```

Links between mirrored pages are relative paths, so follow them with Read. A link to a page that
is not mirrored, such as an image or a talk page, points at the live wiki.

## Use what you read

- Each file starts with YAML frontmatter. Cite its `url`, the live page, in a docs page, comment,
  or commit, never the local path. `revision` and `fetched` tell how fresh the copy is.
- The wiki is written by the modding community, and some pages are wrong or out of date. For a
  Papyrus signature, the compiled script in the install is the stronger source. Treat a claim
  about engine behaviour as a hypothesis to confirm against observed data, and say in the docs
  page which one you relied on.
- The text is CC BY-SA 4.0. Quote a few lines with a citation when that helps. Never copy pages
  or the mirror into the repository.

## When the tool itself breaks

The sync code is the uv project `tools/ck-wiki/`. Its design and the mirror layout are in
`docs/tools/ck-wiki.md`. After changing the converter, raise `CONVERTER_VERSION` and run
`make ck-wiki`; it converts the stored pages again without the network. Check with
`make py-format-check py-lint test-python`, fix what they report, and run them again.
