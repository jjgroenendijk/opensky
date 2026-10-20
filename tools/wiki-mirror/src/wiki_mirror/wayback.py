"""Wayback Machine snapshots of a wiki, for when the live wiki blocks this machine."""

from __future__ import annotations

import json
import re
from http import HTTPStatus
from typing import TYPE_CHECKING
from urllib.parse import unquote, urlencode, urlsplit

from .client import Http, HttpError
from .markup import find_element, inner_html
from .sources import FetchedPage, PageRef, SourceError, utc_now

if TYPE_CHECKING:
    from .sites import Site

WAYBACK = "https://web.archive.org"
CDX_URL = f"{WAYBACK}/cdx/search/cdx"
CDX_PAGE_ROWS = 10000
CONTENT_OPENINGS = (
    r'<div[^>]*class="mw-parser-output"',
    r'<div[^>]*id="mw-content-text"',
)
CATEGORY_LINK = re.compile(r'href="/wiki/Category:([^"#?]+)"')


class SkippedPageError(SourceError):
    """The snapshot holds no page of its own, such as a redirect to another title."""


class WaybackSource:
    """The newest archived capture of each wiki page. Versions are capture timestamps."""

    name = "wayback"
    # The archive misses pages, so a page absent from it may still be on the wiki.
    complete = False

    def __init__(self, site: Site, http: Http) -> None:
        """Read captures of `site` and use `http` for every request."""
        self._site = site
        self._http = http

    def list_pages(self, namespaces: list[int]) -> list[PageRef]:
        """List the newest successful capture of every page in the given namespaces."""
        newest: dict[str, str] = {}
        for prefix in self._url_prefixes(namespaces):
            for original, timestamp in self._captures(prefix):
                title = _title_of(original)
                if title is None or self._site.namespace_of(title) not in namespaces:
                    continue
                newest[title] = max(newest.get(title, ""), timestamp)
        return [
            PageRef(title, self._site.namespace_of(title), f"wb:{timestamp}")
            for title, timestamp in newest.items()
        ]

    def redirects(self, namespaces: list[int]) -> dict[str, str]:
        """Return nothing: the archive does not say which titles are redirects."""
        del namespaces
        return {}

    def fetch(self, page: PageRef) -> FetchedPage:
        """Fetch the raw capture and cut the page content out of the skin around it."""
        timestamp = page.version.removeprefix("wb:")
        url = f"{WAYBACK}/web/{timestamp}id_/{self._site.page_url(page.title)}"
        try:
            response = self._http.get(url)
        except HttpError as error:
            raise SourceError(str(error)) from error
        if response.status != HTTPStatus.OK:
            message = f"{url}: HTTP {response.status}"
            raise SourceError(message)
        html = response.text()
        if 'class="mw-redirectedfrom"' in html:
            message = f"{page.title}: the capture is a redirect to another page"
            raise SkippedPageError(message)
        content = next(
            (
                element
                for opening in CONTENT_OPENINGS
                if (element := find_element(html, opening, "div")) is not None
            ),
            None,
        )
        if content is None:
            message = f"{url}: no page content in the capture"
            raise SourceError(message)
        return FetchedPage(
            title=page.title,
            version=page.version,
            source=self.name,
            source_url=response.url,
            fetched=utc_now(),
            categories=_categories(html),
            html=inner_html(content),
        )

    def _url_prefixes(self, namespaces: list[int]) -> list[str]:
        # The main namespace has no title prefix, so it needs the whole wiki. Without it, one
        # listing per namespace skips the captures of every other game on a shared wiki.
        wiki = f"{self._site.host}/wiki/"
        if 0 in namespaces:
            return [wiki]
        names = self._site.namespace_names
        return [f"{wiki}{names[number].replace(' ', '_')}:" for number in namespaces]

    def _captures(self, prefix: str) -> list[tuple[str, str]]:
        captures = []
        resume_key = ""
        while True:
            params = {
                "url": f"{prefix}*",
                "output": "json",
                "fl": "original,timestamp",
                "filter": ["statuscode:200", "mimetype:text/html"],
                "limit": CDX_PAGE_ROWS,
                "showResumeKey": "true",
            }
            if resume_key:
                params["resumeKey"] = resume_key
            rows = self._cdx(f"{CDX_URL}?{urlencode(params, doseq=True)}")
            # A header row, the captures, then an empty row and the resume key when more remain.
            resume_key = ""
            if rows[-2:-1] == [[]]:
                resume_key = rows[-1][0]
                rows = rows[:-2]
            captures += [(row[0], row[-1]) for row in rows[1:] if row]
            if not resume_key:
                return captures

    def _cdx(self, url: str) -> list[list[str]]:
        try:
            response = self._http.get(url)
        except HttpError as error:
            raise SourceError(str(error)) from error
        if response.status != HTTPStatus.OK:
            message = f"{url}: HTTP {response.status}"
            raise SourceError(message)
        try:
            return json.loads(response.body) if response.body.strip() else []
        except json.JSONDecodeError as error:
            message = f"{url}: the capture index is not JSON"
            raise SourceError(message) from error


def _title_of(original: str) -> str | None:
    parts = urlsplit(original)
    if parts.query or not parts.path.startswith("/wiki/"):
        return None
    title = unquote(parts.path.removeprefix("/wiki/")).replace("_", " ").strip()
    if not title:
        return None
    return title[0].upper() + title[1:]


def _categories(html: str) -> list[str]:
    links = find_element(html, r'<div[^>]*id="mw-normal-catlinks"', "div") or ""
    return [unquote(name).replace("_", " ") for name in CATEGORY_LINK.findall(links)]
