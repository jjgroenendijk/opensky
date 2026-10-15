"""Where pages come from: the live MediaWiki API, or Wayback Machine snapshots of the wiki."""

from __future__ import annotations

import json
import time
from dataclasses import dataclass
from datetime import UTC, datetime
from http import HTTPStatus
from typing import TYPE_CHECKING, Protocol
from urllib.parse import quote, urlencode

from .client import Http, HttpError

if TYPE_CHECKING:
    from collections.abc import Iterator

HOST = "ck.uesp.net"
SITE = f"https://{HOST}"
API_URL = f"{SITE}/w/api.php"
# From the wiki's siteinfo. A title prefix outside this table belongs to the main namespace.
NAMESPACE_NAMES = {
    -2: "Media",
    -1: "Special",
    0: "",
    1: "Talk",
    2: "User",
    3: "User talk",
    4: "CreationKit",
    5: "CreationKit talk",
    6: "File",
    7: "File talk",
    8: "MediaWiki",
    9: "MediaWiki talk",
    10: "Template",
    11: "Template talk",
    12: "Help",
    13: "Help talk",
    14: "Category",
    15: "Category talk",
    710: "TimedText",
    711: "TimedText talk",
    828: "Module",
    829: "Module talk",
    2300: "Gadget",
    2301: "Gadget talk",
    2302: "Gadget definition",
    2303: "Gadget definition talk",
}
NAMESPACE_IDS = {name: number for number, name in NAMESPACE_NAMES.items() if name}
CATEGORY_NAMESPACE = 14
MAXLAG_ATTEMPTS = 5


class SourceError(Exception):
    """A source cannot list or fetch pages."""


@dataclass(frozen=True)
class PageRef:
    """A page as a listing names it. `version` changes whenever the content can have changed."""

    title: str
    namespace: int
    version: str


@dataclass(frozen=True)
class FetchedPage:
    """The rendered content of one page, and where it came from."""

    title: str
    version: str
    source: str
    source_url: str
    fetched: str
    categories: list[str]
    html: str


class Source(Protocol):
    """A place to list and fetch wiki pages."""

    name: str
    # True when a page missing from the listing is gone from the wiki.
    complete: bool

    def list_pages(self, namespaces: list[int]) -> list[PageRef]:
        """List the content pages, without redirects, in the given namespaces."""
        ...

    def redirects(self, namespaces: list[int]) -> dict[str, str]:
        """Map each redirect title to its target, `Title#Section` for a section."""
        ...

    def fetch(self, page: PageRef) -> FetchedPage:
        """Return the rendered HTML of one page."""
        ...


def namespace_of(title: str) -> int:
    """Return the namespace number a title belongs to."""
    prefix, colon, _ = title.partition(":")
    return NAMESPACE_IDS.get(prefix, 0) if colon else 0


def page_url(title: str) -> str:
    """Return the live wiki URL of a title, encoded the way MediaWiki links it."""
    return f"{SITE}/wiki/{quote(title.replace(' ', '_'), safe=';@$!*(),/~:')}"


def utc_now() -> str:
    """Return the current time as an ISO 8601 UTC timestamp."""
    return datetime.now(UTC).replace(microsecond=0).isoformat()


class ApiSource:
    """The MediaWiki API at /w/api.php, which answers with exact revision numbers."""

    name = "api"
    complete = True

    def __init__(self, http: Http) -> None:
        """Use `http` for every request."""
        self._http = http

    def check(self) -> None:
        """Raise `SourceError` when the API does not answer with JSON, as behind a block page."""
        self._query(action="query", meta="siteinfo")

    def list_pages(self, namespaces: list[int]) -> list[PageRef]:
        """List every content page with its latest revision number."""
        pages = []
        for namespace in namespaces:
            params = {
                "generator": "allpages",
                "gapnamespace": namespace,
                "gapfilterredir": "nonredirects",
                "prop": "info",
            }
            for batch in self._continued(params):
                pages += [
                    PageRef(page["title"], page["ns"], f"rev:{page['lastrevid']}")
                    for page in batch.get("pages", [])
                ]
        return pages

    def redirects(self, namespaces: list[int]) -> dict[str, str]:
        """Map every redirect that points at a content page in the given namespaces."""
        targets = {}
        for namespace in namespaces:
            params = {
                "generator": "allpages",
                "gapnamespace": namespace,
                "gapfilterredir": "nonredirects",
                "prop": "redirects",
                "rdprop": "title|fragment",
                "rdlimit": "max",
            }
            for batch in self._continued(params):
                for page in batch.get("pages", []):
                    for redirect in page.get("redirects", []):
                        fragment = redirect.get("fragment")
                        target = page["title"] + (f"#{fragment}" if fragment else "")
                        targets[redirect["title"]] = target
        return targets

    def fetch(self, page: PageRef) -> FetchedPage:
        """Fetch the parser output of the page, without edit links or table of contents."""
        data = self._query(
            action="parse",
            page=page.title,
            prop="text|categories|revid",
            disableeditsection=1,
            disabletoc=1,
        )["parse"]
        return FetchedPage(
            title=data["title"],
            version=f"rev:{data['revid']}",
            source=self.name,
            source_url=page_url(data["title"]),
            fetched=utc_now(),
            categories=[
                entry["category"].replace("_", " ")
                for entry in data.get("categories", [])
                if not entry.get("hidden")
            ],
            html=data["text"],
        )

    def _continued(self, params: dict[str, str | int]) -> Iterator[dict]:
        cursor: dict[str, str] = {}
        while True:
            data = self._query(action="query", gaplimit="max", **params, **cursor)
            yield data.get("query", {})
            if "continue" not in data:
                return
            cursor = data["continue"]

    def _query(self, **params: str | int) -> dict:
        params = {"format": "json", "formatversion": 2, "maxlag": 5, **params}
        url = f"{API_URL}?{urlencode(params)}"
        for attempt in range(MAXLAG_ATTEMPTS):
            data = self._json(url)
            error = data.get("error")
            if error is None:
                return data
            if error.get("code") != "maxlag":
                message = f"{url}: {error.get('code')}: {error.get('info')}"
                raise SourceError(message)
            time.sleep(2.0**attempt)
        message = f"{url}: the wiki stayed lagged after {MAXLAG_ATTEMPTS} attempts"
        raise SourceError(message)

    def _json(self, url: str) -> dict:
        try:
            response = self._http.get(url)
        except HttpError as error:
            raise SourceError(str(error)) from error
        if response.status != HTTPStatus.OK:
            message = f"{url}: HTTP {response.status}"
            raise SourceError(message)
        try:
            return json.loads(response.body)
        except json.JSONDecodeError as error:
            message = f"{url}: the answer is not JSON (a block page?)"
            raise SourceError(message) from error
