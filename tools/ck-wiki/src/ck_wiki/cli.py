"""Download or update an offline Markdown copy of the Creation Kit wiki (ck.uesp.net).

A second run fetches only pages whose revision changed. docs/tools/ck-wiki.md has the
mirror layout and the reasons behind the two sources.
"""

from __future__ import annotations

import argparse
import dataclasses
import re
import shutil
import subprocess
import sys
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import TYPE_CHECKING

from .client import Http
from .convert import (
    CONVERTER_VERSION,
    LICENSE,
    LinkMap,
    frontmatter,
    link_list,
    render_category,
    render_page,
)
from .mirror import INDEX_NAME, Entry, Mirror, State, assign_paths, link_key
from .sources import (
    CATEGORY_NAMESPACE,
    NAMESPACE_NAMES,
    SITE,
    ApiSource,
    PageRef,
    Source,
    SourceError,
    namespace_of,
    utc_now,
)
from .wayback import SkippedPageError, WaybackSource

if TYPE_CHECKING:
    from collections.abc import Callable, Iterable

# Main, CreationKit (the project pages), Help, and Category.
DEFAULT_NAMESPACES = [0, 4, 12, 14]
# A subpage named by a language code, such as "Actor Script/fr".
TRANSLATION = re.compile(r"/[a-z]{2}(?:-[a-z]+)?$")
WAYBACK_MIN_DELAY = 1.0
PROGRESS_EVERY = 200
SHOWN_FAILURES = 10


def log(message: str) -> None:
    """Print one progress line straight away."""
    print(message, flush=True)


def git(*args: str, cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    """Run git and return its result; a missing git reads as a failed command."""
    program = shutil.which("git")
    if program is None:
        return subprocess.CompletedProcess(args, returncode=127, stdout="", stderr="no git")
    return subprocess.run([program, *args], cwd=cwd, capture_output=True, text=True, check=False)


def default_out() -> Path:
    """Return `.cache/ck-wiki` in the main checkout of the current repository.

    Every worktree shares it, so the wiki downloads once per machine.
    """
    result = git("rev-parse", "--path-format=absolute", "--git-common-dir")
    if result.returncode != 0:
        message = "not inside a git checkout; pass --out"
        raise SourceError(message)
    return Path(result.stdout.strip()).parent / ".cache" / "ck-wiki"


def ensure_not_committable(out: Path) -> None:
    """Refuse a mirror folder that git would track: the wiki text is not ours to commit."""
    existing = next(folder for folder in (out, *out.parents) if folder.exists())
    checkout = git("rev-parse", "--show-toplevel", cwd=existing)
    if checkout.returncode != 0:
        return
    if git("check-ignore", "-q", str(out), cwd=existing).returncode != 0:
        message = (
            f"{out} is inside the checkout {checkout.stdout.strip()} and git does not ignore it. "
            "The wiki must never be committed; choose an ignored folder such as .cache/."
        )
        raise SourceError(message)


def parse_args(argv: list[str]) -> argparse.Namespace:
    """Read the command line."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--out", type=Path, help="mirror folder [<main checkout>/.cache/ck-wiki]")
    parser.add_argument(
        "--source",
        choices=["auto", "api", "wayback"],
        default="auto",
        help="auto uses the wiki API and falls back to the Wayback Machine when it is blocked",
    )
    parser.add_argument(
        "--namespace",
        type=int,
        action="append",
        choices=sorted(NAMESPACE_NAMES),
        help=f"namespace number to mirror; repeat for more [{DEFAULT_NAMESPACES}]",
    )
    parser.add_argument("--translations", action="store_true", help="also mirror /fr, /ja, ...")
    parser.add_argument("--limit", type=int, help="fetch at most this many pages (for a test)")
    parser.add_argument("--workers", type=int, default=4, help="parallel requests and pandoc runs")
    parser.add_argument("--delay", type=float, default=0.2, help="seconds between requests")
    parser.add_argument(
        "--reconvert", action="store_true", help="convert every stored page again, offline"
    )
    return parser.parse_args(argv)


def choose_source(choice: str, delay: float) -> Source:
    """Return the live API when it answers, else the Wayback Machine (unless `api` was asked)."""
    if choice in {"auto", "api"}:
        api = ApiSource(Http(delay))
        try:
            api.check()
        except SourceError as error:
            if choice == "api":
                raise
            log(f"[WARNING] the wiki API does not answer ({error}).")
            log("[WARNING] Falling back to Wayback Machine snapshots; they can be older.")
        else:
            return api
    return WaybackSource(Http(max(delay, WAYBACK_MIN_DELAY)))


def run_parallel[T, R](
    workers: int, items: list[T], work: Callable[[T], R], label: str
) -> Iterable[tuple[T, R | Exception]]:
    """Run `work` over `items` on worker threads and yield each item with its result or error."""
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {pool.submit(work, item): item for item in items}
        for done, future in enumerate(as_completed(futures), start=1):
            try:
                result: R | Exception = future.result()
            except (
                SourceError,
                OSError,
                RuntimeError,
                ValueError,
                subprocess.SubprocessError,
            ) as error:
                result = error
            if done % PROGRESS_EVERY == 0 or done == len(items):
                log(f"[INFO] {label} {done}/{len(items)}")
            yield futures[future], result


class Sync:
    """One run that brings the mirror up to date."""

    def __init__(
        self, args: argparse.Namespace, source: Source, mirror: Mirror, pandoc: str
    ) -> None:
        """Keep what the run needs."""
        self.args = args
        self.source = source
        self.mirror = mirror
        self.pandoc = pandoc
        self.namespaces = args.namespace or DEFAULT_NAMESPACES
        self.failures: list[str] = []

    def run(self) -> int:
        """Fetch changed pages, convert what needs it, and remove what is gone."""
        state = self.mirror.load_state()
        listed = self.list_pages()
        fetched = self.fetch(listed, state)
        if self.source.complete:
            self.forget_missing(listed, state)
            state.redirects = self.source.redirects(self.namespaces)
        present = [title for title in state.pages if self.mirror.has_page(title)]
        paths = assign_paths(present + self.listless_categories(present, state))
        key = link_key(paths, state.redirects)
        links = LinkMap(paths, state.redirects)
        reconvert_all = (
            self.args.reconvert or state.converter != CONVERTER_VERSION or state.link_key != key
        )
        convert = [
            title
            for title in paths
            if reconvert_all
            or title in fetched
            or namespace_of(title) == CATEGORY_NAMESPACE
            or state.paths.get(title) != paths[title]
            or not self.mirror.markdown_exists(paths[title])
        ]
        changed = self.convert(convert, links, state)
        self.mirror.remove_markdown(set(state.paths.values()) - set(paths.values()))
        self.write_index(list(paths), links)
        state.converter, state.link_key, state.paths = CONVERTER_VERSION, key, paths
        self.mirror.save_state(state)
        return self.report(len(present), len(fetched), changed)

    def list_pages(self) -> list[PageRef]:
        """List the pages to mirror, without translations unless asked."""
        pages = self.source.list_pages(self.namespaces)
        if not self.args.translations:
            pages = [page for page in pages if not TRANSLATION.search(page.title)]
        log(f"[INFO] {len(pages)} pages listed through the {self.source.name} source")
        return pages

    def fetch(self, listed: list[PageRef], state: State) -> set[str]:
        """Fetch every listed page whose stored copy is missing or older."""
        wanted = [page for page in listed if self.needs_fetch(page, state.pages.get(page.title))]
        wanted = wanted[: self.args.limit] if self.args.limit is not None else wanted
        log(f"[INFO] {len(wanted)} pages to fetch")

        def work(page: PageRef) -> list[str]:
            fetched = dataclasses.replace(self.source.fetch(page), title=page.title)
            self.mirror.store_page(fetched)
            return fetched.categories

        done = set()
        for page, result in run_parallel(self.args.workers, wanted, work, "fetched"):
            if isinstance(result, SkippedPageError):
                continue
            if isinstance(result, Exception):
                self.failures.append(f"fetch {page.title}: {result}")
                continue
            state.pages[page.title] = Entry(page.version, self.source.name, result)
            done.add(page.title)
        return done

    def needs_fetch(self, page: PageRef, entry: Entry | None) -> bool:
        """Decide whether to fetch a page. An archived capture never replaces a live copy."""
        if entry is None or not self.mirror.has_page(page.title):
            return True
        if self.source.name == "wayback" and entry.source == "api":
            return False
        return entry.version != page.version

    def forget_missing(self, listed: list[PageRef], state: State) -> None:
        """Drop stored pages that the wiki no longer lists."""
        wanted = {page.title for page in listed}
        for title in [title for title in state.pages if title not in wanted]:
            self.mirror.forget_page(title)
            del state.pages[title]

    def listless_categories(self, present: list[str], state: State) -> list[str]:
        """Return the categories that pages use but that have no page or redirect of their own."""
        if CATEGORY_NAMESPACE not in self.namespaces:
            return []
        used = {f"Category:{name}" for title in present for name in state.pages[title].categories}
        return sorted(used - set(present) - set(state.redirects))

    def convert(self, titles: list[str], links: LinkMap, state: State) -> int:
        """Write the Markdown of the given pages and return how many files changed."""
        members: dict[str, list[str]] = defaultdict(list)
        for title in links.paths:
            for category in state.pages[title].categories if title in state.pages else []:
                members[f"Category:{category}"].append(title)

        def work(title: str) -> bool:
            path = links.paths[title]
            if title not in state.pages:
                text = render_category(title, path, links, members[title])
            else:
                page = self.mirror.load_page(title)
                text = render_page(page, path, links, members.get(title, []), self.pandoc)
            return self.mirror.write_markdown(path, text)

        changed = 0
        for title, result in run_parallel(self.args.workers, titles, work, "converted"):
            if isinstance(result, Exception):
                self.failures.append(f"convert {title}: {result}")
            elif result:
                changed += 1
        return changed

    def write_index(self, present: list[str], links: LinkMap) -> None:
        """Write index.md, which links every mirrored page by namespace."""
        fields = {
            "title": "Creation Kit wiki (offline mirror)",
            "url": f"{SITE}/wiki/Main_Page",
            "source": "Creation Kit wiki (ck.uesp.net)",
            "license": LICENSE,
            "synced": utc_now(),
            "pages": len(present),
        }
        sections = [frontmatter(fields), "# Creation Kit wiki"]
        for namespace in self.namespaces:
            titles = [title for title in present if namespace_of(title) == namespace]
            if titles:
                heading = NAMESPACE_NAMES[namespace] or "Main"
                sections.append(f"## {heading}\n\n" + link_list(titles, INDEX_NAME, links))
        self.mirror.write_markdown(INDEX_NAME, "\n\n".join(sections) + "\n")

    def report(self, present: int, fetched: int, changed: int) -> int:
        """Print the outcome and return the exit status."""
        log(f"[INFO] {present} pages in {self.mirror.root}")
        log(f"[INFO] {fetched} fetched, {changed} Markdown files written")
        if not self.failures:
            log("[ OK ] Creation Kit wiki mirror is up to date")
            return 0
        for failure in self.failures[:SHOWN_FAILURES]:
            log(f"[ERROR] {failure}")
        log(f"[ERROR] {len(self.failures)} pages failed; run again to retry them")
        return 1


def main(argv: list[str] | None = None) -> int:
    """Run one sync and return the exit status."""
    args = parse_args(sys.argv[1:] if argv is None else argv)
    pandoc = shutil.which("pandoc")
    if pandoc is None:
        log("[ERROR] pandoc not found. Install it with `brew install pandoc` or `make bootstrap`.")
        return 1
    try:
        source = choose_source(args.source, args.delay)
        out = (args.out or default_out()).resolve()
        ensure_not_committable(out)
        mirror = Mirror(out)
        log(f"[INFO] mirror folder: {mirror.root}")
        return Sync(args, source, mirror, pandoc).run()
    except SourceError as error:
        log(f"[ERROR] {error}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
