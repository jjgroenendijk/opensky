// The title menu's game settings: the credits scroll speed and the last part of the
// version text. See docs/engine/main-menu.md.

public import OpenSkyGameData

nonisolated public struct TitleMenuSettings: Equatable, Sendable {
    /// `fCreditsScrollSpeed`: what the credits movie's `getScrollSpeed()` returns.
    public var creditsScrollSpeed: Float = 2
    /// `iUpdateESMVersion`: the last part of the version the main menu shows.
    public var updateESMVersion = 8

    public static let vanilla = Self()

    public init() {}

    public static func resolve(store: GameSettingStore) -> Self {
        var settings = vanilla
        store.read("fCreditsScrollSpeed", into: &settings, \.creditsScrollSpeed)
        store.read("iUpdateESMVersion", into: &settings, \.updateESMVersion)
        return settings
    }

    /// The main menu's version text: `OpenSky.<iUpdateESMVersion>`, as the game ends its own
    /// version with that number.
    public var versionText: String {
        "OpenSky.\(updateESMVersion)"
    }
}
