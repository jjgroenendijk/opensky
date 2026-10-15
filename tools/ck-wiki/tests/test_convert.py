import json
import shutil

import pytest

from ck_wiki.convert import LinkMap, frontmatter, prepare_html, render_page
from ck_wiki.sources import FetchedPage

LINKS = LinkMap(
    paths={
        "Actor Script": "Actor Script.md",
        "Category:Papyrus": "Category/Papyrus.md",
        "AI Data Tab": "AI Data Tab.md",
    },
    redirects={"Aggression": "AI Data Tab#Aggression"},
)


def test_links_to_mirrored_pages_become_relative_paths() -> None:
    html = prepare_html(
        '<a href="/wiki/Actor_Script" title="Actor Script">x</a>', "index.md", LINKS
    )
    assert html == '<a href="Actor%20Script.md">x</a>'


def test_links_from_a_namespace_folder_climb_out_of_it() -> None:
    html = prepare_html('<a href="/wiki/Actor_Script#Events">x</a>', "Category/Papyrus.md", LINKS)
    assert 'href="../Actor%20Script.md#Events"' in html


def test_redirects_resolve_to_the_target_section() -> None:
    html = prepare_html('<a href="/wiki/Aggression">x</a>', "index.md", LINKS)
    assert 'href="AI%20Data%20Tab.md#Aggression"' in html


def test_pages_not_mirrored_link_to_the_live_wiki() -> None:
    html = prepare_html(
        '<a href="/wiki/File:A.jpg"><img src="/w/images/a.jpg" srcset="/w/b.jpg 2x"></a>',
        "index.md",
        LINKS,
    )
    assert 'href="https://ck.uesp.net/wiki/File:A.jpg"' in html
    assert 'src="https://ck.uesp.net/w/images/a.jpg"' in html
    assert "srcset" not in html


def test_highlighted_blocks_without_a_language_are_papyrus() -> None:
    html = prepare_html(
        '<div class="mw-highlight mw-content-ltr"><pre>a</pre></div>', "x.md", LINKS
    )
    assert '<pre><code class="papyrus">a</code></pre>' in html


def test_highlighted_blocks_keep_their_language() -> None:
    html = prepare_html(
        '<div class="mw-highlight mw-highlight-lang-ini"><pre>a</pre></div>', "x.md", LINKS
    )
    assert '<code class="ini">' in html


def test_wiki_chrome_is_removed() -> None:
    html = prepare_html(
        '<div id="toc"><ul><li>1</li></ul></div><h2>A<span class="mw-editsection">'
        "<span>[</span>edit<span>]</span></span></h2><p><br /></p><!-- report -->",
        "x.md",
        LINKS,
    )
    assert html == "<h2>A</h2>"


def test_a_first_row_of_header_cells_becomes_the_table_header() -> None:
    html = prepare_html(
        "<table><tbody><tr><th>A</th></tr><tr><td>1</td></tr></tbody></table>", "x.md", LINKS
    )
    assert (
        html
        == "<table><thead><tr><th>A</th></tr></thead><tbody><tr><td>1</td></tr></tbody></table>"
    )


def test_frontmatter_values_are_quoted_safely() -> None:
    text = frontmatter({"title": 'Say "hi": now', "categories": ["A", "B"]})
    lines = text.splitlines()
    assert lines[0] == lines[-1] == "---"
    assert json.loads(lines[1].removeprefix("title: ")) == 'Say "hi": now'


@pytest.mark.skipif(shutil.which("pandoc") is None, reason="needs pandoc")
def test_render_page_writes_frontmatter_title_and_fenced_code() -> None:
    page = FetchedPage(
        title="AI Data Tab",
        version="rev:1",
        source="api",
        source_url="https://ck.uesp.net/wiki/AI_Data_Tab",
        fetched="2026-01-01T00:00:00+00:00",
        categories=["Papyrus"],
        html='<h1>Top</h1><div class="mw-highlight"><pre>Event OnInit()</pre></div>',
    )
    text = render_page(page, "AI Data Tab.md", LINKS, [], shutil.which("pandoc") or "")
    assert 'url: "https://ck.uesp.net/wiki/AI_Data_Tab"' in text
    assert "\n# AI Data Tab\n\n## Top\n" in text
    assert "```papyrus\nEvent OnInit()\n```" in text
    assert "- [Category:Papyrus](Category/Papyrus.md)" in text
