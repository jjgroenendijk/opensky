"""The mirror on disk: Markdown files, the fetched HTML they come from, and the sync state."""

from __future__ import annotations

import hashlib
import json
import re
from dataclasses import asdict, dataclass, field
from typing import TYPE_CHECKING

from .sources import FetchedPage

if TYPE_CHECKING:
    from pathlib import Path

    from .sites import Site

STATE_FORMAT = 1
INDEX_NAME = "index.md"
SYNC_DIR = ".sync"
# Characters a macOS or Windows file name cannot hold, or that confuse a shell.
UNSAFE_NAME = re.compile(r'[\\:*?"<>|\x00-\x1f]')


@dataclass
class Entry:
    """What the state remembers about one stored page."""

    version: str
    source: str
    categories: list[str] = field(default_factory=list)


@dataclass
class State:
    """Everything a sync needs to know about the previous one."""

    redirects: dict[str, str] = field(default_factory=dict)
    pages: dict[str, Entry] = field(default_factory=dict)
    paths: dict[str, str] = field(default_factory=dict)


def page_path(title: str, site: Site) -> str:
    """Return the mirror path for a title: namespace folder, then subpages as folders."""
    namespace = site.namespace_of(title)
    name = title.partition(":")[2] if namespace else title
    parts = [UNSAFE_NAME.sub("_", part).strip().strip(".") or "_" for part in name.split("/")]
    if namespace:
        parts.insert(0, site.namespace_names[namespace])
    return "/".join(parts) + ".md"


def assign_paths(titles: list[str], site: Site) -> dict[str, str]:
    """Give every title its own path, also on a case-insensitive file system."""
    used = {INDEX_NAME}
    paths = {}
    for title in sorted(titles):
        base = page_path(title, site).removesuffix(".md")
        path = f"{base}.md"
        number = 2
        while path.casefold() in used:
            path = f"{base} ({number}).md"
            number += 1
        used.add(path.casefold())
        paths[title] = path
    return paths


class Mirror:
    """Reads and writes one mirror folder."""

    def __init__(self, root: Path) -> None:
        """Use `root` as the mirror folder; it is created on the first write."""
        self.root = root
        self._sync = root / SYNC_DIR
        self._state_file = self._sync / "state.json"

    def load_state(self) -> State:
        """Return the state of the previous sync, or an empty one for a new mirror."""
        if not self._state_file.is_file():
            return State()
        data = json.loads(self._state_file.read_text(encoding="utf-8"))
        if data.get("format") != STATE_FORMAT:
            return State()
        return State(
            redirects=data["redirects"],
            pages={title: Entry(**entry) for title, entry in data["pages"].items()},
            paths=data["paths"],
        )

    def save_state(self, state: State) -> None:
        """Write the state; a crash before this leaves the previous state in place."""
        data = {"format": STATE_FORMAT, **asdict(state)}
        self._write_atomic(self._state_file, json.dumps(data, indent=1, ensure_ascii=False))

    def has_page(self, title: str) -> bool:
        """Return whether the fetched HTML of a title is stored."""
        return self._page_file(title).is_file()

    def store_page(self, page: FetchedPage) -> None:
        """Keep the fetched HTML, so a later sync can convert again without the network."""
        self._write_atomic(self._page_file(page.title), json.dumps(asdict(page)))

    def load_page(self, title: str) -> FetchedPage:
        """Return the stored fetched HTML of a title."""
        data = json.loads(self._page_file(title).read_text(encoding="utf-8"))
        return FetchedPage(**data)

    def forget_page(self, title: str) -> None:
        """Delete the stored fetched HTML of a title."""
        self._page_file(title).unlink(missing_ok=True)

    def write_markdown(self, path: str, text: str) -> bool:
        """Write a Markdown file only when its text changed. Return whether it changed."""
        target = self.root / path
        if target.is_file() and target.read_text(encoding="utf-8") == text:
            return False
        self._write_atomic(target, text)
        return True

    def remove_markdown(self, paths: set[str]) -> None:
        """Delete Markdown files, then any folder they leave empty."""
        for path in paths:
            target = self.root / path
            target.unlink(missing_ok=True)
            for folder in target.parents:
                if folder == self.root or not folder.is_relative_to(self.root):
                    break
                if any(folder.iterdir()):
                    break
                folder.rmdir()

    def _page_file(self, title: str) -> Path:
        digest = hashlib.sha256(title.encode()).hexdigest()
        return self._sync / "pages" / digest[:2] / f"{digest}.json"

    @staticmethod
    def _write_atomic(target: Path, text: str) -> None:
        target.parent.mkdir(parents=True, exist_ok=True)
        temporary = target.with_name(f".{target.name}.tmp")
        temporary.write_text(text, encoding="utf-8")
        temporary.replace(target)
