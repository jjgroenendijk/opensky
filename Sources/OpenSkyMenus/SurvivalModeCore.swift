// The Survival Mode plugin's prompt, answered ahead of time. The plugin's quest
// script asks once, when `Survival_PlayerHasBeenPrompted` is 0, and a Yes sets
// `Survival_ModeToggle`. See docs/engine/survival-mode.md.

import Foundation

/// How a session answers the prompt: with a fixed answer, or by letting the plugin ask.
nonisolated public enum SurvivalModeAnswer: String, CaseIterable, Sendable {
    case on
    case off
    case ask

    /// `OPENSKY_SURVIVAL_MODE` overrides the settings for one run, such as an agent launch.
    public static let environmentKey = "OPENSKY_SURVIVAL_MODE"

    public static func forced(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Self? {
        environment[environmentKey].flatMap { Self(rawValue: $0.lowercased()) }
    }
}

/// The plugin's four globals. Nil fields mean the plugin is not loaded.
nonisolated public struct SurvivalModeGlobals: Equatable, Sendable {
    public var prompted: Bool
    /// `SRVT`, the player's choice; the plugin starts or stops the mode to match.
    public var toggle: Bool
    /// `SRVE`, whether the mode runs now.
    public var enabled: Bool
    /// `SRVS`, whether the plugin lets the player choose yet.
    public var canBeEnabled: Bool

    public init(prompted: Bool, toggle: Bool, enabled: Bool, canBeEnabled: Bool) {
        self.prompted = prompted
        self.toggle = toggle
        self.enabled = enabled
        self.canBeEnabled = canBeEnabled
    }
}

nonisolated public enum SurvivalModeCore {
    public static let promptedEditorID = "Survival_PlayerHasBeenPrompted"
    public static let toggleEditorID = "Survival_ModeToggle"
    public static let enabledEditorID = "Survival_ModeEnabled"
    public static let canBeEnabledEditorID = "Survival_ModeCanBeEnabled"

    public enum Step: Equatable, Sendable {
        case none
        /// Write what a press of Yes or No writes: the toggle, then the prompted flag.
        case answer(Bool)
        /// The session holds a choice the setting does not show, from the prompt or a save.
        case mirror(Bool)
    }

    public static func step(
        globals: SurvivalModeGlobals, answer: SurvivalModeAnswer, setting: Bool
    ) -> Step {
        guard globals.prompted else {
            switch answer {
            case .ask: return .none
            case .on: return .answer(true)
            case .off: return .answer(false)
            }
        }
        return globals.toggle == setting ? .none : .mirror(globals.toggle)
    }

    public static func answer(ask: Bool, setting: Bool) -> SurvivalModeAnswer {
        ask ? .ask : setting ? .on : .off
    }
}
