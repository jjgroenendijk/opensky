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
    /// `sConfirmContinue`: the question before Continue loads the last save while a game
    /// is in progress.
    public var confirmContinueText = "Continue from your last saved game?"

    /// `sCantLoadSettings` and `sCantLoadControls`: the OK box when the player's settings
    /// file, or its controls, could not be read.
    public var cantLoadSettingsText = "Unable to load settings. Defaults will be used."
    public var cantLoadControlsText = "Unable to load controls. Defaults will be used."

    public static let vanilla = Self()

    public init() {}

    public static func resolve(
        store: GameSettingStore, text: GameTextResolver = { _ in nil }
    ) -> Self {
        var settings = vanilla
        store.read("fCreditsScrollSpeed", into: &settings, \.creditsScrollSpeed)
        store.read("iUpdateESMVersion", into: &settings, \.updateESMVersion)
        store.read("sConfirmNew", into: &settings, \.confirmNewText, text: text)
        store.read("sConfirmContinue", into: &settings, \.confirmContinueText, text: text)
        store.read("sCantLoadSettings", into: &settings, \.cantLoadSettingsText, text: text)
        store.read("sCantLoadControls", into: &settings, \.cantLoadControlsText, text: text)
        return settings
    }

    /// The main menu's version text: `OpenSky.<iUpdateESMVersion>`, as the game ends its own
    /// version with that number.
    public var versionText: String {
        "OpenSky.\(updateESMVersion)"
    }
}
