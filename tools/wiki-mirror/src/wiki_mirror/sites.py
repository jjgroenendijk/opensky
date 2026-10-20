"""The wikis the tool mirrors: where each one lives, and which of its namespaces to keep."""

from __future__ import annotations

from dataclasses import dataclass
from urllib.parse import quote

# Namespaces every MediaWiki has, from the siteinfo of both wikis. 4 and 5 are the project
# namespaces, whose name each wiki chooses.
COMMON_NAMESPACES = {
    -2: "Media",
    -1: "Special",
    0: "",
    1: "Talk",
    2: "User",
    3: "User talk",
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


@dataclass(frozen=True)
class Site:
    """One wiki. A title prefix outside `namespace_names` belongs to the main namespace."""

    key: str
    host: str
    name: str
    # From the siteinfo `rightsinfo` of the wiki.
    license: str
    namespace_names: dict[int, str]
    # Namespaces to mirror. Talk, user, file, and template pages hold no reference text.
    mirrored: tuple[int, ...]
    # The language of a highlighted code block whose HTML names none.
    plain_code_language: str

    @property
    def url(self) -> str:
        """Return the root URL of the wiki."""
        return f"https://{self.host}"

    @property
    def api_url(self) -> str:
        """Return the URL of the MediaWiki API."""
        return f"{self.url}/w/api.php"

    @property
    def source_label(self) -> str:
        """Return the `source` value of the frontmatter, such as `UESP wiki (en.uesp.net)`."""
        return f"{self.name} ({self.host})"

    def namespace_of(self, title: str) -> int:
        """Return the namespace number a title belongs to."""
        prefix, colon, _ = title.partition(":")
        if not colon:
            return 0
        ids = {name: number for number, name in self.namespace_names.items() if name}
        return ids.get(prefix, 0)

    def page_url(self, title: str) -> str:
        """Return the live wiki URL of a title, encoded the way MediaWiki links it."""
        return f"{self.url}/wiki/{quote(title.replace(' ', '_'), safe=';@$!*(),/~:')}"


CREATION_KIT = Site(
    key="ck",
    host="ck.uesp.net",
    name="Creation Kit wiki",
    license="CC BY-SA 4.0 (https://creativecommons.org/licenses/by-sa/4.0/)",
    namespace_names={**COMMON_NAMESPACES, 4: "CreationKit", 5: "CreationKit talk"},
    # Main, CreationKit (the project pages), Help, and Category.
    mirrored=(0, 4, 12, 14),
    # The wiki has no Papyrus highlighter, so its Papyrus blocks carry no language class.
    plain_code_language="papyrus",
)

UESP = Site(
    key="uesp",
    host="en.uesp.net",
    name="UESP wiki",
    license="CC BY-SA 2.5 (https://creativecommons.org/licenses/by-sa/2.5/)",
    namespace_names={
        **COMMON_NAMESPACES,
        4: "UESPWiki",
        5: "UESPWiki talk",
        134: "Skyrim",
        135: "Skyrim talk",
        142: "Skyrim Mod",
        143: "Skyrim Mod talk",
    },
    # Skyrim (the game and its add-ons) and Skyrim Mod (file formats and modding). The other
    # games, Lore, and the categories of every game are far larger and not about this engine.
    mirrored=(134, 142),
    plain_code_language="text",
)

SITES = {site.key: site for site in (CREATION_KIT, UESP)}
