---
name: consulting-uesp-wikis
description: Looks up the Creation Kit wiki (ck.uesp.net) and the UESP wiki (en.uesp.net) in
  their local Markdown mirrors, and syncs them with make ck-wiki and make uesp-wiki. The CK wiki
  covers Papyrus scripts, functions, and events, condition functions, forms and record fields,
  editor tabs, and game settings. UESP covers Skyrim game rules, items, NPCs, quests, and
  formulas (Skyrim:) and file formats and record layouts (Skyrim Mod:, Tes5Mod:). Use whenever a
  task needs either wiki, such as checking a Papyrus signature, a condition function, a skill
  formula, or the UESP Mod File Format page, instead of fetching the wiki or the Wayback Machine.
---

# Consulting the UESP wikis

Two wikis are mirrored as Markdown in `.cache/` of the main checkout, which every worktree
shares. Read pages there. Do not fetch `ck.uesp.net` or `en.uesp.net` pages: the sites answer
scripts with HTTP 403 or a Cloudflare page (`docs/tools/environment.md`), and the mirrors already
hold every page the tool keeps.

| Mirror | Wiki | Holds | Sync |
| --- | --- | --- | --- |
| `.cache/ck-wiki/` | Creation Kit wiki | Papyrus, condition functions, forms, editor | `make ck-wiki` |
| `.cache/uesp-wiki/` | UESP wiki | `Skyrim:` game pages, `Skyrim Mod:` formats and modding | `make uesp-wiki` |

Pick the wiki by the question. Papyrus and the editor: the CK wiki. How the game plays (a
formula, an NPC, a quest stage) or a file layout: UESP. When unsure, search both.

## Find the mirror

```sh
cache="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.cache"
ls "$cache/ck-wiki/index.md" "$cache/uesp-wiki/index.md"
```

If an `index.md` is missing, or the task needs an edit made to the wiki in the last few days,
sync that wiki first with its `make` target. Run it in a background shell. A first run fetches
every page and takes most of an hour (about 2,800 CK pages, about 7,000 UESP pages); a later run
fetches only changed pages and takes a few minutes. It needs `uv` and `pandoc`, which
`make bootstrap` installs. When the API is blocked, it falls back to the Wayback Machine by
itself; do not fetch the archive by hand.

The UESP mirror holds only the `Skyrim` and `Skyrim Mod` namespaces. A link to another game,
`Lore:`, or `Books:` points at the live wiki; say that the page is not mirrored rather than
fetching it.

## Find a page

The file name is the page title. A page outside the main namespace sits in a folder named after
its namespace. Common title patterns:

| Looking for | File |
| --- | --- |
| A Papyrus function or event | `ck-wiki/GetActorValue - Actor.md`, `ck-wiki/OnHit - ObjectReference.md` |
| A Papyrus script object | `ck-wiki/Actor Script.md` |
| A condition function | `ck-wiki/GetIsID.md` (no script suffix); all of them: `ck-wiki/Condition Functions.md` |
| A form type or editor window | `ck-wiki/Armor.md`, `ck-wiki/AI Data Tab.md` |
| A record or file layout | `uesp-wiki/Skyrim Mod/Mod File Format.md`, `uesp-wiki/Skyrim Mod/Mod File Format/NPC_.md` |
| A game rule, skill, or item | `uesp-wiki/Skyrim/Alchemy.md`, `uesp-wiki/Skyrim/Lydia.md` |
| Everything in a category | `Category/<Name>.md` lists its member pages, such as `uesp-wiki/Category/Skyrim-NPCs.md` |

`Tes5Mod:` and `T5:` are aliases of `Skyrim Mod:`, and `SR:` of `Skyrim:`; the files use the full
name. When the exact title is unknown, search. File names first, then text:

```sh
find "$cache/uesp-wiki" -name '*.md' -not -path '*/.sync/*' | grep -i 'file format'
grep -rli --include='*.md' --exclude-dir=.sync 'OnMagicEffectApply' "$cache/ck-wiki"
```

Links between mirrored pages are relative paths, so follow them with Read. A link to a page that
is not mirrored, such as an image or a talk page, points at the live wiki.

## Use what you read

- Each file starts with YAML frontmatter. Cite its `url`, the live page, in a docs page, comment,
  or commit, never the local path. `revision` and `fetched` tell how fresh the copy is.
- Both wikis are written by the community, and some pages are wrong or out of date. For a Papyrus
  signature, the compiled script in the install is the stronger source. For a byte layout, the
  real files are. Treat a claim about engine behaviour as a hypothesis to confirm against observed
  data, and say in the docs page which one you relied on.
- The text is CC BY-SA (the `license` field gives the version). Quote a few lines with a citation
  when that helps. Never copy pages or a mirror into the repository.

## When a page reads wrong

Fix it in the tool, never in the mirror file. A sync overwrites the file, and the same fault is
usually on other pages too. The sync code is the uv project `tools/wiki-mirror/`; each wiki's
settings are in `sites.py`, and the conversion steps and their reasons are in
`docs/tools/offline-wikis.md`.

1. Find the cause in the stored HTML under `.sync/pages/` and fix the converter.
2. Run `make ck-wiki` and `make uesp-wiki`. Each converts every stored page again; only changed
   pages are fetched.
3. Search both mirrors for the fault, not only the page you saw, for example
   `grep -rlF --include='*.md' '[TABLE]' "$cache/ck-wiki" "$cache/uesp-wiki"`. Fix and repeat
   until none is left.
4. Run `make py-format py-lint` and fix what it reports.
