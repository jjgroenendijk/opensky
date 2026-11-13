// The title menu's game settings: the credits scroll speed, the last part of the
// version text, and the New question. See docs/engine/main-menu.md.

public import OpenSkyGameData

nonisolated public struct TitleMenuSettings: Equatable, Sendable {
    /// `fCreditsScrollSpeed`: what the credits movie's `getScrollSpeed()` returns.
    public var creditsScrollSpeed: Float = 2
    /// `iUpdateESMVersion`: the last part of the version the main menu shows.
    public var updateESMVersion = 8
    /// `sConfirmNew`: the question before New starts a game.
    public var confirmNewText = "Start a new game?"

    public static let vanilla = Self()

    public init() {}

    public static func resolve(
        store: GameSettingStore, text: GameTextResolver = { _ in nil }
    ) -> Self {
        var settings = vanilla
        store.read("fCreditsScrollSpeed", into: &settings, \.creditsScrollSpeed)
        store.read("iUpdateESMVersion", into: &settings, \.updateESMVersion)
        store.read("sConfirmNew", into: &settings, \.confirmNewText, text: text)
        return settings
    }

    /// The main menu's version text: `OpenSky.<iUpdateESMVersion>`, as the game ends its own
    /// version with that number.
    public var versionText: String {
        "OpenSky.\(updateESMVersion)"
    }
}
