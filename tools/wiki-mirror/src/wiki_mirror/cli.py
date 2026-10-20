"""Download or update an offline Markdown copy of the Creation Kit wiki or the UESP wiki.

A second run fetches only pages whose revision changed, then converts every stored page
again. docs/tools/offline-wikis.md has the mirror layout and the reasons behind the two sources.
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
    LinkMap,
    frontmatter,
    link_list,
    render_category,
    render_page,
)
from .mirror import INDEX_NAME, Entry, Mirror, State, assign_paths
from .sites import SITES, Site
from .sources import ApiSource, PageRef, Source, SourceError, utc_now
from .wayback import SkippedPageError, WaybackSource

if TYPE_CHECKING:
    from collections.abc import Callable, Iterable

# A subpage named by a language code, such as "Actor Script/fr". Only English is mirrored.
TRANSLATION = re.compile(r"/[a-z]{2}(?:-[a-z]+)?$")
# Seconds between request starts. Both wikis are community servers, so at most five API
# requests a second; the Wayback Machine asks for about one a second.
API_DELAY = 0.2
WAYBACK_DELAY = 1.0
# Parallel requests and pandoc runs. Four keep the request spacing busy while each answer
# takes about half a second.
WORKERS = 4
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


def default_out(site: Site) -> Path:
    """Return `.cache/<site>-wiki` in the main checkout of the current repository.

    Every worktree shares it, so the wiki downloads once per machine.
    """
    result = git("rev-parse", "--path-format=absolute", "--git-common-dir")
    if result.returncode != 0:
        message = "not inside a git checkout; pass --out"
        raise SourceError(message)
    return Path(result.stdout.strip()).parent / ".cache" / f"{site.key}-wiki"


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
    parser.add_argument("--site", choices=sorted(SITES), default="ck", help="the wiki to mirror")
    parser.add_argument(
        "--out", type=Path, help="mirror folder [<main checkout>/.cache/<site>-wiki]"
    )
    parser.add_argument(
        "--source",
        choices=["auto", "api", "wayback"],
        default="auto",
        help="auto uses the wiki API and falls back to the Wayback Machine when it is blocked",
    )
    return parser.parse_args(argv)


def choose_source(site: Site, choice: str) -> Source:
    """Return the live API when it answers, else the Wayback Machine (unless `api` was asked)."""
    if choice in {"auto", "api"}:
        api = ApiSource(site, Http(API_DELAY))
        try:
            api.check()
        except SourceError as error:
            if choice == "api":
                raise
            log(f"[WARNING] the wiki API does not answer ({error}).")
            log("[WARNING] Falling back to Wayback Machine snapshots; they can be older.")
        else:
            return api
    return WaybackSource(site, Http(WAYBACK_DELAY))


def run_parallel[T, R](
    items: list[T], work: Callable[[T], R], label: str
) -> Iterable[tuple[T, R | Exception]]:
    """Run `work` over `items` on worker threads and yield each item with its result or error."""
    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
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

    def __init__(self, site: Site, source: Source, mirror: Mirror, pandoc: str) -> None:
        """Keep what the run needs."""
        self.site = site
        self.namespaces = list(site.mirrored)
        self.source = source
        self.mirror = mirror
        self.pandoc = pandoc
        self.failures: list[str] = []

    def run(self) -> int:
        """Fetch changed pages, convert every stored page, and remove what is gone."""
        state = self.mirror.load_state()
        listed = self.list_pages()
        fetched = self.fetch(listed, state)
        if self.source.complete:
            self.forget_missing(listed, state)
            state.redirects = self.source.redirects(self.namespaces)
        present = [title for title in state.pages if self.mirror.has_page(title)]
        paths = assign_paths(present + self.listless_categories(present, state), self.site)
        links = LinkMap(self.site, paths, state.redirects)
        changed = self.convert(list(paths), links, state)
        self.mirror.remove_markdown(set(state.paths.values()) - set(paths.values()))
        self.write_index(list(paths), links)
        state.paths = paths
        self.mirror.save_state(state)
        return self.report(len(present), len(fetched), changed)

    def list_pages(self) -> list[PageRef]:
        """List the English pages to mirror."""
        pages = self.source.list_pages(self.namespaces)
        pages = [page for page in pages if not TRANSLATION.search(page.title)]
        log(f"[INFO] {len(pages)} pages listed through the {self.source.name} source")
        return pages

    def fetch(self, listed: list[PageRef], state: State) -> set[str]:
        """Fetch every listed page whose stored copy is missing or older."""
        wanted = [page for page in listed if self.needs_fetch(page, state.pages.get(page.title))]
        log(f"[INFO] {len(wanted)} pages to fetch")

        def work(page: PageRef) -> list[str]:
            fetched = dataclasses.replace(self.source.fetch(page), title=page.title)
            self.mirror.store_page(fetched)
            return fetched.categories

        done = set()
        for page, result in run_parallel(wanted, work, "fetched"):
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
        for title, result in run_parallel(titles, work, "converted"):
            if isinstance(result, Exception):
                self.failures.append(f"convert {title}: {result}")
            elif result:
                changed += 1
        return changed

    def write_index(self, present: list[str], links: LinkMap) -> None:
        """Write index.md, which links every mirrored page by namespace."""
        site = self.site
        fields = {
            "title": f"{site.name} (offline mirror)",
            "url": f"{site.url}/wiki/Main_Page",
            "source": site.source_label,
            "license": site.license,
            "synced": utc_now(),
            "pages": len(present),
        }
        sections = [frontmatter(fields), f"# {site.name}"]
        for namespace in dict.fromkeys([*self.namespaces, 14]):
            titles = [title for title in present if site.namespace_of(title) == namespace]
            if titles:
                heading = site.namespace_names[namespace] or "Main"
                sections.append(f"## {heading}\n\n" + link_list(titles, INDEX_NAME, links))
        self.mirror.write_markdown(INDEX_NAME, "\n\n".join(sections) + "\n")

    def report(self, present: int, fetched: int, changed: int) -> int:
        """Print the outcome and return the exit status."""
        log(f"[INFO] {present} pages in {self.mirror.root}")
        log(f"[INFO] {fetched} fetched, {changed} Markdown files written")
        if not self.failures:
            log(f"[ OK ] {self.site.name} mirror is up to date")
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
        site = SITES[args.site]
        source = choose_source(site, args.source)
        out = (args.out or default_out(site)).resolve()
        ensure_not_committable(out)
        mirror = Mirror(out)
        log(f"[INFO] mirror folder: {mirror.root}")
        return Sync(site, source, mirror, pandoc).run()
    except SourceError as error:
        log(f"[ERROR] {error}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
