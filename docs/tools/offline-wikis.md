---
type: Tool
title: Offline wikis
description: How `make ck-wiki` and `make uesp-wiki` mirror the Creation Kit wiki and the UESP
  wiki as Markdown, where the mirrors live, what each file holds, and why they read the
  MediaWiki API and the Wayback Machine.
tags: [tool, reference, papyrus, creation-kit, uesp]
---

# Offline wikis

Two community wikis document Skyrim, and both run on MediaWiki:

- The [Creation Kit wiki](https://ck.uesp.net) documents Papyrus functions, events, condition
  functions, record forms, and editor behaviour.
- The [UESP wiki](https://en.uesp.net) documents the game itself (items, NPCs, quests, game
  rules) in its `Skyrim:` pages, and the file formats and modding in its `Skyrim Mod:` pages
  (alias `Tes5Mod:`), such as `Skyrim Mod:Mod File Format`.

One tool keeps a local Markdown copy of each, so an agent or a person can search it with `grep`
and read it without the network.

## Use

```sh
make ck-wiki                            # the Creation Kit wiki
make uesp-wiki                          # the Skyrim pages of the UESP wiki
make uesp-wiki ARGS='--source wayback'  # force the Wayback Machine
```

The first run fetches every page: about 2,800 for the Creation Kit wiki, about 7,000 for UESP.
A later run fetches only the pages that changed. Every run converts all stored pages again, which
takes a minute or two, so a converter change reaches every page without a new download.

The tool has three options: `--site` (`ck` or `uesp`), `--out`, and `--source`. Each wiki's
host and namespaces are in `tools/wiki-mirror/src/wiki_mirror/sites.py`; the request rate and the
number of workers are constants in `cli.py`. Each carries its reason.

The tool needs `uv` and `pandoc`; `make bootstrap` installs both. Its code is the uv project in
`tools/wiki-mirror/`.

## Where the mirrors live

The mirrors are `.cache/ck-wiki/` and `.cache/uesp-wiki/` in the main checkout. Every worktree
shares that folder, so each wiki downloads once per machine. From any worktree:

```sh
cache="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.cache"
ls "$cache/ck-wiki/index.md" "$cache/uesp-wiki/index.md"
```

`.cache/` is gitignored. The wiki text is licensed CC BY-SA and is not our work, so a mirror is
never committed. Two checks enforce this. The tool refuses an `--out` folder inside a checkout
unless git ignores it. `make no-game-content` fails on a tracked Markdown file whose frontmatter has
the mirror's `fetched_from:` key.

## What each mirror holds

The Creation Kit mirror holds the main, `CreationKit`, `Help`, and `Category` namespaces.

The UESP wiki covers every Elder Scrolls game, with more than 120,000 articles. The mirror holds
only the `Skyrim` and `Skyrim Mod` namespaces. `Skyrim:` also holds the Dawnguard, Hearthfire, and
Dragonborn pages. The other games, `Lore:`, and `Books:` are left out, because they say nothing
about this engine and would make a sync many hours long. Its `Category:` pages are left out too,
because they list every game. The tool writes a member list for each category the mirrored pages
use instead.

Translations (`/fr`, `/ja`, and other language subpages) are skipped. Talk, user, file, and
template pages are never mirrored.

## Layout

| Path | Holds |
| --- | --- |
| `index.md` | A link to every page, grouped by namespace |
| `<Title>.md` | A main-namespace page, such as `GetActorValue - Actor.md` |
| `<Namespace>/<Title>.md` | A page in another namespace, such as `Skyrim Mod/Mod File Format.md` |
| `Category/<Name>.md` | A category page, followed by a list of its member pages |
| | For a category with no mirrored page, a generated member list (`generated:` in the frontmatter) |
| `<Title>/<Subpage>.md` | A subpage, such as `SKSE/Plugin ABI.md` |
| `.sync/` | The fetched HTML of every page and the state of the last sync |

The file name is the page title. Characters a file name cannot hold become `_`. Two titles that
differ only in case get `(2)` added, because the data volume is case-insensitive.

## A page file

Each file starts with YAML frontmatter:

```yaml
---
title: "GetActorValue - Actor"
url: "https://ck.uesp.net/wiki/GetActorValue_-_Actor"
source: "Creation Kit wiki (ck.uesp.net)"
license: "CC BY-SA 4.0 (https://creativecommons.org/licenses/by-sa/4.0/)"
revision: "rev:25061"
fetched_from: "api"
fetched: "2026-10-15T15:31:55+00:00"
categories: ["Scripting", "Papyrus"]
---
```

`url` is the live page; cite it in a docs page or a commit. `revision` is `rev:<id>` from the API
or `wb:<timestamp>` from a Wayback capture, which then also has `archived_url`.

The body is GitHub Markdown. A link to a mirrored page is a relative path; a link to anything
else, such as an image, a talk page, or another UESP namespace, points at the live wiki. Code
blocks are fenced with their language. The Creation Kit wiki has no Papyrus highlighter, so a
highlighted block without a language there is marked `papyrus`.

## Sources

The live Creation Kit wiki sits behind Cloudflare. It answers `/wiki/<Page>` with HTTP 403 to
scripts, but its MediaWiki API at `/w/api.php` still answers (`docs/tools/environment.md`). The
UESP API at `https://en.uesp.net/w/api.php` answers the same way. The API is also the better
source: it lists every page with its latest revision number, so a sync fetches only the pages that
changed. It also gives each page's redirects, so a link to a redirect resolves to the target file
and section.

When the API does not answer with JSON, `--source auto` (the default) falls back to the Wayback
Machine. It lists captures through the CDX index and takes the newest capture of each page. For
UESP it lists only the URLs of the mirrored namespaces, such as `en.uesp.net/wiki/Skyrim:*`;
captures under an alias such as `Tes5Mod:` are not found. An archived copy can be older than the
wiki, the archive misses some pages, and it does not say which titles are redirects. So in that
mode a capture never replaces a page that came from the API, and pages missing from the archive
are kept.

The sync keeps at least 0.2 seconds between API requests and 1 second between archive requests,
and it sends a user agent that names the project.

## Conversion

`.sync/` keeps the rendered HTML of each page. Conversion runs pandoc (`html` to `gfm` without raw
HTML) with the Lua filter `tools/wiki-mirror/src/wiki_mirror/markdown.lua`. Each step exists
because the plain conversion lost or garbled content:

| Step | Why |
| --- | --- |
| Remove the table of contents, edit links, and image zoom links | Wiki chrome, not content |
| Remove navigation boxes (UESP `navbox` tables) | Every page in a series repeats the same box of links |
| Give scheme-relative links such as `//images.uesp.net/...` an `https:` scheme | Markdown readers do not resolve them |
| Make a first row of header cells the table header, also in a table inside a layout table | Otherwise the table gets an empty header |
| Fill each position a row or column span covers with an empty cell | The gfm writer drops spans, so the next cells slid into the wrong column |
| Unwrap a one-row or one-column table into its cells | GFM cannot hold the notice and layout boxes; pandoc wrote `[TABLE]` |
| Flatten other table cells to one line, `/` between parts | GFM table cells hold one line; pandoc wrote `[TABLE]` |
| Fence every code block with its language | The gfm writer drops languages it does not know, such as `papyrus` |
| Drop line breaks that start or end a block | They became lone `\` lines |
| Rewrite section links to GitHub heading anchors | MediaWiki ids such as `#Undo_.28CTRL.2BZ.29` match no Markdown heading |
| Move level 1 headings in a page down one level | The page title stays the only level 1 heading |
| Drop trailing spaces and repeated blank lines outside code | Noise from the HTML layout |

Fix the output only through the tool, never by editing a mirror file: the next sync overwrites the
file, and the same fault is on other pages too. After a converter change, run the sync again for
each wiki; it applies the change to every page.
