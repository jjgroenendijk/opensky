nonisolated public enum HUDMode: String, CaseIterable, Sendable {
    case stealth = "StealthMode"
    case swimming = "Swimming"
    case horse = "HorseMode"
    case warHorse = "WarHorseMode"
    case cart = "CartMode"
    case movementDisabled = "MovementDisabled"

    /// The clips OpenSky also shows and hides that this mode hides, as the movie's
    /// element list says. OpenSky's own switches must not show them again.
    public var hiddenClips: Set<HUDModeClip> {
        switch self {
        case .stealth, .swimming: []
        case .horse: [.stamina, .itemInfo]
        case .warHorse: [.itemInfo]
        case .cart, .movementDisabled: Set(HUDModeClip.allCases)
        }
    }
}

/// The movie clips whose `_visible` both OpenSky and the HUD modes write.
nonisolated public enum HUDModeClip: CaseIterable, Sendable {
    case health
    case magicka
    case stamina
    case enemyHealth
    /// The item name, its info line, and the gray bar between them.
    case itemInfo
}
