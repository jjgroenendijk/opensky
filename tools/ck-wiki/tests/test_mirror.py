from pathlib import Path

from ck_wiki.markup import find_element, inner_html, remove_elements
from ck_wiki.mirror import Entry, Mirror, State, assign_paths, page_path
from ck_wiki.sources import FetchedPage, namespace_of
from ck_wiki.wayback import _categories, _title_of


def test_namespaces_become_folders_and_subpages_nest() -> None:
    assert page_path("Category:Papyrus") == "Category/Papyrus.md"
    assert page_path("SKSE/Plugin ABI") == "SKSE/Plugin ABI.md"
    assert page_path('What? A "b"') == "What_ A _b_.md"
    assert page_path("Notanamespace:Thing") == "Notanamespace_Thing.md"


def test_titles_that_differ_only_in_case_get_their_own_file() -> None:
    paths = assign_paths(["GetAV", "GetAv", "Index"])
    assert paths == {"GetAV": "GetAV.md", "GetAv": "GetAv (2).md", "Index": "Index (2).md"}


def test_namespace_of_reads_known_prefixes_only() -> None:
    assert namespace_of("Category:Papyrus") == 14
    assert namespace_of("Help:Contents") == 12
    assert namespace_of("Papyrus: Basics") == 0


def test_state_and_pages_survive_a_round_trip(tmp_path: Path) -> None:
    mirror = Mirror(tmp_path)
    state = State(converter=2, link_key="k", pages={"A": Entry("rev:3", "api", ["Papyrus"])})
    mirror.save_state(state)
    page = FetchedPage("A", "rev:3", "api", "https://x", "t", ["Papyrus"], "<p>a</p>")
    mirror.store_page(page)
    assert mirror.load_state() == state
    assert mirror.load_page("A") == page


def test_markdown_is_rewritten_only_when_it_changes(tmp_path: Path) -> None:
    mirror = Mirror(tmp_path)
    assert mirror.write_markdown("Category/A.md", "a")
    assert not mirror.write_markdown("Category/A.md", "a")
    mirror.remove_markdown({"Category/A.md"})
    assert not (tmp_path / "Category").exists()


def test_nested_elements_are_cut_whole() -> None:
    html = '<div id="toc"><div>x</div></div><p>keep</p><div id="toc">y</div>'
    assert remove_elements(html, r'<div id="toc"', "div") == "<p>keep</p>"
    element = find_element('<div class="a"><div>b</div></div>c', r'<div class="a"', "div")
    assert element is not None
    assert inner_html(element) == "<div>b</div>"


def test_wayback_urls_map_to_titles() -> None:
    assert _title_of("https://ck.uesp.net/wiki/Actor_Script") == "Actor Script"
    assert _title_of("http://ck.uesp.net/wiki/category:Papyrus") == "Category:Papyrus"
    assert _title_of("https://ck.uesp.net/wiki/A?oldid=3") is None
    assert _title_of("https://ck.uesp.net/w/index.php") is None


def test_wayback_categories_skip_hidden_ones() -> None:
    html = (
        '<div id="mw-normal-catlinks"><a href="/wiki/Category:Papyrus">P</a></div>'
        '<div id="mw-hidden-catlinks"><a href="/wiki/Category:Hidden">H</a></div>'
    )
    assert _categories(html) == ["Papyrus"]
