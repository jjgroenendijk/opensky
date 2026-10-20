"""Find and cut whole HTML elements, nested ones included, without a full HTML parser."""

from __future__ import annotations

import re
from functools import cache


@cache
def _tag_pattern(tag: str) -> re.Pattern[str]:
    return re.compile(rf"<(/?){tag}\b[^>]*?(/?)>", re.IGNORECASE)


def element_end(html: str, start: int, tag: str) -> int:
    """Return the index just past the element of type `tag` that opens at `start`."""
    depth = 0
    for match in _tag_pattern(tag).finditer(html, start):
        closing, self_closing = match.group(1), match.group(2)
        if self_closing:
            continue
        depth += -1 if closing else 1
        if depth == 0:
            return match.end()
    return len(html)


def find_element(html: str, opening: str, tag: str) -> str | None:
    """Return the first element whose opening tag matches the regex `opening`."""
    match = re.search(opening, html)
    if match is None:
        return None
    return html[match.start() : element_end(html, match.start(), tag)]


def inner_html(element: str) -> str:
    """Return the content of an element without its own opening and closing tags."""
    start = element.find(">") + 1
    end = element.rfind("</")
    return element[start:end] if end >= start else element[start:]


def remove_elements(html: str, opening: str, tag: str) -> str:
    """Cut every element whose opening tag matches the regex `opening`."""
    pattern = re.compile(opening)
    pieces = []
    position = 0
    while (match := pattern.search(html, position)) is not None:
        pieces.append(html[position : match.start()])
        position = element_end(html, match.start(), tag)
    pieces.append(html[position:])
    return "".join(pieces)
