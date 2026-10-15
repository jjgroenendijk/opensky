---
type: Tool
title: Offline Creation Kit wiki
description: How `make ck-wiki` mirrors the Creation Kit wiki as Markdown, where the mirror lives,
  what each file holds, and why it reads the MediaWiki API and the Wayback Machine.
tags: [tool, reference, papyrus, creation-kit]
---

# Offline Creation Kit wiki

The [Creation Kit wiki](https://ck.uesp.net) documents Papyrus functions, events, condition
functions, record forms, and editor behaviour. `make ck-wiki` keeps a local copy of it as
Markdown, so an agent or a person can search it with `grep` and read it without the network.

## Use

```sh
make ck-wiki                          # first run: all pages; later runs: changed pages only
make ck-wiki ARGS='--source wayback'  # force the Wayback Machine
make ck-wiki ARGS='--reconvert'       # convert the stored HTML again, offline
make ck-wiki ARGS='--help'            # every option
```

The tool needs `uv` and `pandoc`; `make bootstrap` installs both. Its code is the uv project in
`tools/ck-wiki/`.

## Where the mirror lives

The mirror is in `.cache/ck-wiki/` of the main checkout. Every worktree shares that folder, so
the wiki downloads once per machine. From any worktree:

```sh
wiki="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.cache/ck-wiki"
```

`.cache/` is gitignored. The wiki text is licensed CC BY-SA 4.0 and is not our work, so the mirror
is never committed. Two checks enforce this. The tool refuses an `--out` folder inside a checkout
unless git ignores it. `make no-game-content` fails on a tracked Markdown file whose frontmatter has
the mirror's `fetched_from:` key.

## Layout

| Path | Holds |
| --- | --- |
| `index.md` | A link to every page, grouped by namespace |
| `<Title>.md` | A main-namespace page, such as `GetActorValue - Actor.md` |
| `Category/<Name>.md` | A category page, followed by a list of its member pages |
| | For a category with no page on the wiki, a generated member list (`generated:` in the frontmatter) |
| `CreationKit/`, `Help/` | The project and help namespaces |
| `<Title>/<Subpage>.md` | A subpage, such as `SKSE/Plugin ABI.md` |
| `.sync/` | The fetched HTML of every page and the state of the last sync |

The file name is the page title. Characters a file name cannot hold become `_`. Two titles that
differ only in case get `(2)` added, because the data volume is case-insensitive.

Translations (`/fr`, `/ja`, and other language subpages) are skipped unless `--translations` is
given. Talk, user, file, and template pages are never mirrored.

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
else, such as an image or a talk page, points at the live wiki. Code blocks are fenced with their
language. The wiki has no Papyrus highlighter, so a highlighted block without a language is
marked `papyrus`.

## Sources

The live wiki sits behind Cloudflare. It answers `/wiki/<Page>` with HTTP 403 to scripts, but its
MediaWiki API at `/w/api.php` still answers (`docs/tools/environment.md`). The API is also the
better source: it lists every page with its latest revision number, so a sync fetches only the
pages that changed. It also gives each page's redirects, so a link to a redirect resolves to the
target file and section.

When the API does not answer with JSON, `--source auto` (the default) falls back to the Wayback
Machine. It lists captures through the CDX index and takes the newest capture of each page. That
copy can be older than the wiki, the archive misses some pages, and it does not say which titles
are redirects. So in that mode a capture never replaces a page that came from the API, and pages
missing from the archive are kept.

The sync keeps at least 0.2 seconds between API requests and 1 second between archive requests,
and it sends a user agent that names the project.

## Conversion

`.sync/` keeps the rendered HTML of each page. Conversion runs pandoc (`html` to `gfm` without raw
HTML) with the Lua filter `tools/ck-wiki/src/ck_wiki/markdown.lua`. Each step exists because the
plain conversion lost or garbled content:

| Step | Why |
| --- | --- |
| Remove the table of contents, edit links, and image zoom links | Wiki chrome, not content |
| Make a first row of header cells the table header | Otherwise the table gets an empty header |
| Unwrap a one-row or one-column table into its cells | GFM cannot hold the notice and layout boxes; pandoc wrote `[TABLE]` |
| Flatten other table cells to one line, `/` between parts | GFM table cells hold one line; pandoc wrote `[TABLE]` |
| Fence every code block with its language | The gfm writer drops languages it does not know, such as `papyrus` |
| Drop line breaks that start or end a block | They became lone `\` lines |
| Rewrite section links to GitHub heading anchors | MediaWiki ids such as `#Undo_.28CTRL.2BZ.29` match no Markdown heading |
| Move level 1 headings in a page down one level | The page title stays the only level 1 heading |
| Drop trailing spaces and repeated blank lines outside code | Noise from the HTML layout |

Fix the output only through the tool, never by editing a mirror file: the next sync overwrites the
file, and the same fault is on other pages too. A change to the converter raises
`CONVERTER_VERSION` in `tools/ck-wiki/src/ck_wiki/convert.py`. The next sync then converts every
stored page again without fetching it.
