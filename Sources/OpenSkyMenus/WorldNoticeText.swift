// The HUD's announcements of world changes: a location found or cleared, a spell or
// word learned, a dragon soul, and a new map marker, from their string settings.
// See docs/engine/journal.md#hud-notices.

import OpenSkyGameData
import OpenSkyScriptingInterface

nonisolated public enum WorldNoticeText: String, GameSettingTextKey {
    case discovered = "sDiscoveredText"
    case cleared = "sCleared"
    case spellLearned = "sSpellAdded"
    case wordLearned = "sShoutAdded"
    case dragonSoul = "sDragonSoulAcquired"
    /// `%i` is the count.
    case oneDragonSoul = "sSingleDragonSoulCount"
    case dragonSouls = "sMultipleDragonSoulCount"
    case mapUpdated = "sMapMarkerAdded"

    public var fallback: String {
        switch self {
        case .discovered: "discovered"
        case .cleared: "Cleared"
        case .spellLearned: "New Spell Learned"
        case .wordLearned: "Word of Power Learned"
        case .dragonSoul: "Dragon Soul Absorbed"
        case .oneDragonSoul: "%i Dragon Soul"
        case .dragonSouls: "%i Dragon Souls"
        case .mapUpdated: "Map updated."
        }
    }
}

/// How one notice shows: a big centred notice, or one notification line.
nonisolated public enum WorldNoticeShape: Equatable, Sendable {
    case big(HUDBigNotice)
    case line(String)

    /// Which line goes over which is OpenSky's reading.
    public init(_ notice: WorldNotice, texts: GameSettingTexts<WorldNoticeText>) {
        switch notice {
        case let .locationDiscovered(name):
            self = .big(HUDBigNotice(title: name, status: texts[.discovered]))
        case let .locationCleared(name):
            self = .big(HUDBigNotice(title: name, status: texts[.cleared]))
        case let .spellLearned(name):
            self = .big(HUDBigNotice(title: name, status: texts[.spellLearned]))
        case let .wordLearned(word):
            self = .big(HUDBigNotice(kind: .shout, title: word, status: texts[.wordLearned]))
        case let .dragonSoulAbsorbed(souls):
            let count = texts[souls == 1 ? .oneDragonSoul : .dragonSouls]
            self = .big(HUDBigNotice(
                title: texts[.dragonSoul], status: SettingTextFormat.fill(count, ["\(souls)"])
            ))
        case .mapMarkerAdded:
            self = .line(texts[.mapUpdated])
        }
    }
}
