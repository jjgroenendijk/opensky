"""Turn the rendered HTML of a wiki page into GitHub Markdown with YAML frontmatter."""

from __future__ import annotations

import json
import posixpath
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING
from urllib.parse import quote, unquote

from .markup import remove_elements

if TYPE_CHECKING:
    from .sites import Site
    from .sources import FetchedPage

WIKI_HREF = re.compile(r'href="/wiki/([^"#]*)(#[^"]*)?"')
SITE_RELATIVE = re.compile(r'(href|src)="/(?!/)')
# Images sit on another host, linked without a scheme: `//images.uesp.net/...`.
SCHEME_RELATIVE = re.compile(r'(href|src)="//')
SRCSET = re.compile(r'\ssrcset="[^"]*"')
HIGHLIGHT_BLOCK = re.compile(
    r'<div[^>]*class="mw-highlight(?:[^"]*?mw-highlight-lang-([\w-]+))?[^"]*"[^>]*>\s*<pre[^>]*>'
)
# MediaWiki writes a section id byte as a dot and two hex digits: "(" becomes ".28".
MEDIAWIKI_ESCAPE = re.compile(r"\.([0-9A-F]{2})")
SAME_PAGE_HREF = re.compile(r'href="(#[^"]*)"')
PLAIN_PRE = re.compile(r"<pre\b[^>]*>(?!<code)")
LINK_TITLE = re.compile(r'(<a\b[^>]*?)\stitle="[^"]*"')
EMPTY_PARAGRAPH = re.compile(r"<p>\s*(?:<br\s*/?>\s*)*</p>")
LEADING_BREAK = re.compile(r"<p>\s*<br\s*/?>")
# A line break that ends a block, or a run of them, becomes a stray backslash line in Markdown.
TRAILING_BREAKS = re.compile(r"(?:\s*<br\s*/?>)+\s*(?=</(?:p|li|td|th|dd|div)>)")
REPEATED_BREAKS = re.compile(r"(?:<br\s*/?>\s*){2,}")
# A table whose first body row holds only header cells: that row becomes the header.
HEADER_ROW = re.compile(
    r"(<table\b[^>]*>\s*)<tbody>\s*(<tr\b[^>]*>(?:(?!</tr>).)*?</tr>)", re.DOTALL
)
PANDOC_TIMEOUT = 120
MARKDOWN_FILTER = Path(__file__).with_name("markdown.lua")


@dataclass(frozen=True)
class LinkMap:
    """Where each mirrored title lives, and where each redirect points."""

    site: Site
    paths: dict[str, str]
    redirects: dict[str, str]

    def local_href(self, title: str, fragment: str, here: str) -> str | None:
        """Return a link from the file `here` to `title`, or None when it is not mirrored."""
        target = self.redirects.get(title, title)
        target, _, redirect_fragment = target.partition("#")
        path = self.paths.get(target)
        if path is None:
            return None
        relative = posixpath.relpath(path, posixpath.dirname(here) or ".")
        anchor = fragment or (f"#{redirect_fragment}" if redirect_fragment else "")
        return quote(relative) + heading_anchor(anchor)


def heading_anchor(fragment: str) -> str:
    """Turn a MediaWiki section id, such as `#Undo_.28CTRL.2BZ.29`, into a GitHub heading anchor."""
    if not fragment.lstrip("#"):
        return ""
    text = MEDIAWIKI_ESCAPE.sub(lambda match: chr(int(match.group(1), 16)), fragment.lstrip("#"))
    text = unquote(text).replace("_", " ").strip().lower()
    return "#" + re.sub(r"[^\w\- ]", "", text).replace(" ", "-")


def prepare_html(html: str, here: str, links: LinkMap) -> str:
    """Drop wiki chrome, mark code blocks, and point links at mirrored files or the live wiki."""
    site = links.site
    html = re.sub(r"<!--.*?-->", "", html, flags=re.DOTALL)
    html = remove_elements(html, r'<div[^>]*id="toc"', "div")
    html = remove_elements(html, r'<span[^>]*class="mw-editsection"', "span")
    html = remove_elements(html, r'<div[^>]*class="magnify"', "div")
    html = remove_elements(html, r'<table[^>]*class="navbox[\s"]', "table")
    html = HIGHLIGHT_BLOCK.sub(lambda match: _code_opening(match, site), html)
    html = PLAIN_PRE.sub("<pre><code>", html)
    html = re.sub(r"</pre>", "</code></pre>", html)
    html = re.sub(r"</code></code></pre>", "</code></pre>", html)

    def rewrite(match: re.Match[str]) -> str:
        title = unquote(match.group(1)).replace("_", " ")
        fragment = match.group(2) or ""
        href = links.local_href(title, fragment, here)
        return f'href="{href or site.url + "/wiki/" + match.group(1) + fragment}"'

    html = SAME_PAGE_HREF.sub(lambda match: f'href="{heading_anchor(match.group(1))}"', html)
    html = WIKI_HREF.sub(rewrite, html)
    html = SRCSET.sub("", html)
    html = LINK_TITLE.sub(r"\1", html)
    html = EMPTY_PARAGRAPH.sub("", html)
    html = LEADING_BREAK.sub("<p>", html)
    html = TRAILING_BREAKS.sub("", html)
    html = REPEATED_BREAKS.sub("<br>", html)
    html = HEADER_ROW.sub(_promote_header, html)
    html = SCHEME_RELATIVE.sub(r'\1="https://', html)
    return SITE_RELATIVE.sub(lambda match: f'{match.group(1)}="{site.url}/', html)


def _code_opening(match: re.Match[str], site: Site) -> str:
    language = match.group(1) or site.plain_code_language
    return f'<pre><code class="{language}">'


def _promote_header(match: re.Match[str]) -> str:
    table, row = match.group(1), match.group(2)
    if "<th" not in row or "<td" in row:
        return match.group(0)
    return f"{table}<thead>{row}</thead><tbody>"


def html_to_markdown(pandoc: str, html: str) -> str:
    """Convert HTML to GitHub Markdown without raw HTML left in it."""
    # The page title is the only level-1 heading, so a level-1 heading in the content moves down.
    shift = "1" if re.search(r"<h1\b", html) else "0"
    result = subprocess.run(
        [
            pandoc,
            "--from=html",
            "--to=gfm-raw_html",
            "--wrap=none",
            f"--shift-heading-level-by={shift}",
            f"--lua-filter={MARKDOWN_FILTER}",
        ],
        input=html,
        capture_output=True,
        text=True,
        check=False,
        timeout=PANDOC_TIMEOUT,
    )
    if result.returncode != 0:
        message = f"pandoc failed: {result.stderr.strip()}"
        raise RuntimeError(message)
    return tidy_markdown(result.stdout)


def tidy_markdown(text: str) -> str:
    """Drop trailing spaces and repeated blank lines, but never inside a code fence."""
    lines: list[str] = []
    fence = ""
    for line in text.splitlines():
        marker = re.match(r"\s*(`{3,})", line)
        if fence:
            lines.append(line)
            if marker and marker.group(1) == fence and not line.strip().strip("`"):
                fence = ""
            continue
        if marker:
            fence = marker.group(1)
        stripped = line.rstrip()
        if stripped or (lines and lines[-1]):
            lines.append(stripped)
    return "\n".join(lines).strip()


def frontmatter(fields: dict[str, object]) -> str:
    """Write YAML frontmatter. JSON scalars and lists are valid YAML, so quoting is safe."""
    lines = [f"{key}: {json.dumps(value, ensure_ascii=False)}" for key, value in fields.items()]
    return "---\n" + "\n".join(lines) + "\n---"


def render_page(
    page: FetchedPage, here: str, links: LinkMap, members: list[str], pandoc: str
) -> str:
    """Return the whole Markdown file for one page."""
    fields: dict[str, object] = {
        "title": page.title,
        "url": links.site.page_url(page.title),
        "source": links.site.source_label,
        "license": links.site.license,
        "revision": page.version,
        "fetched_from": page.source,
        "fetched": page.fetched,
        "categories": page.categories,
    }
    if page.source != "api":
        fields["archived_url"] = page.source_url
    body = html_to_markdown(pandoc, prepare_html(page.html, here, links))
    parts = [frontmatter(fields), f"# {page.title}", body]
    if members:
        parts.append("## Pages in this category\n\n" + link_list(members, here, links))
    if page.categories:
        names = [f"Category:{name}" for name in page.categories]
        parts.append("## Categories\n\n" + link_list(names, here, links))
    return "\n\n".join(part for part in parts if part) + "\n"


def render_category(title: str, here: str, links: LinkMap, members: list[str]) -> str:
    """Return a member list for a category that the wiki has no page for."""
    fields: dict[str, object] = {
        "title": title,
        "url": links.site.page_url(title),
        "source": links.site.source_label,
        "license": links.site.license,
        "generated": "member list built from the categories of the mirrored pages",
    }
    listing = "## Pages in this category\n\n" + link_list(members, here, links)
    return "\n\n".join([frontmatter(fields), f"# {title}", listing]) + "\n"


def link_list(titles: list[str], here: str, links: LinkMap) -> str:
    """Return a Markdown list that links each title, locally when it is mirrored."""
    items = []
    for title in sorted(titles, key=str.casefold):
        href = links.local_href(title, "", here) or links.site.page_url(title)
        items.append(f"- [{_escape(title)}]({href})")
    return "\n".join(items)


def _escape(text: str) -> str:
    return re.sub(r"([\\\[\]*_`])", r"\\\1", text)
