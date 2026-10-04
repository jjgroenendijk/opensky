// The player settings OpenSky owns: one typed definition per row of the vanilla
// Gameplay, Display, and Audio pages, plus OpenSky's own rows. The row lists were
// measured from quest_journal.swf. See docs/engine/settings.md.

import Foundation

nonisolated public enum PlayerSettingGroup: String, CaseIterable, Sendable {
    case gameplay, display, audio, controls, opensky

    public var title: String {
        switch self {
        case .gameplay: "Gameplay"
        case .display: "Display"
        case .audio: "Audio"
        case .controls: "Controls"
        case .opensky: "OpenSky"
        }
    }
}

nonisolated public enum PlayerSettingKind: Equatable, Sendable {
    case toggle
    case slider(range: ClosedRange<Double>, step: Double)
    /// The option texts are menu tokens; the stored value is the option index.
    case choice(options: [String])

    /// The vanilla row's `movieType`: 0 slider, 1 stepper, 2 checkbox.
    public var movieType: Int {
        switch self {
        case .slider: 0
        case .choice: 1
        case .toggle: 2
        }
    }
}

nonisolated public struct PlayerSettingID: RawRepresentable, Hashable, Comparable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

nonisolated public struct PlayerSettingDefinition: Equatable, Sendable {
    public let id: PlayerSettingID
    public let group: PlayerSettingGroup
    public let kind: PlayerSettingKind
    /// The vanilla row text, such as `$Invert Y`, or plain text for an OpenSky row.
    public let title: String
    public let defaultValue: Double
    /// False while no engine system reads the value yet; it is still stored.
    public let isApplied: Bool

    public init(
        id: PlayerSettingID,
        group: PlayerSettingGroup,
        kind: PlayerSettingKind,
        title: String,
        defaultValue: Double,
        isApplied: Bool
    ) {
        self.id = id
        self.group = group
        self.kind = kind
        self.title = title
        self.defaultValue = defaultValue
        self.isApplied = isApplied
    }

    /// The value this setting can hold, or nil for a value that is not a number.
    public func clamp(_ value: Double) -> Double? {
        guard value.isFinite else { return nil }
        switch kind {
        case .toggle:
            return value >= 0.5 ? 1 : 0
        case let .slider(range, _):
            return min(max(value, range.lowerBound), range.upperBound)
        case let .choice(options):
            guard !options.isEmpty else { return nil }
            return Double(min(max(Int(value.rounded()), 0), options.count - 1))
        }
    }

    /// One step left (-1) or right (+1). A toggle flips and a choice wraps, as the
    /// vanilla checkbox and stepper do; a slider stops at its ends.
    public func stepped(_ value: Double, by direction: Int) -> Double {
        switch kind {
        case .toggle:
            return value >= 0.5 ? 0 : 1
        case let .slider(range, step):
            let next = value + Double(direction) * step
            return min(max(next, range.lowerBound), range.upperBound)
        case let .choice(options):
            guard !options.isEmpty else { return value }
            let count = options.count
            return Double(((Int(value.rounded()) + direction) % count + count) % count)
        }
    }
}

nonisolated extension PlayerSettingID {
    public static let invertLook = Self("gameplay.invertY")
    public static let lookSensitivity = Self("gameplay.lookSensitivity")
    public static let difficulty = Self("gameplay.difficulty")
    public static let floatingMarkers = Self("gameplay.showFloatingMarkers")
    public static let saveOnRest = Self("gameplay.saveOnRest")
    public static let saveOnWait = Self("gameplay.saveOnWait")
    public static let saveOnTravel = Self("gameplay.saveOnTravel")
    public static let saveOnPause = Self("gameplay.saveOnPause")
    public static let hudOpacity = Self("display.hudOpacity")
    public static let crosshair = Self("display.crosshair")
    public static let compass = Self("opensky.compass")
    public static let dialogueSubtitles = Self("display.dialogueSubtitles")
    public static let generalSubtitles = Self("display.generalSubtitles")
    public static let masterVolume = Self("audio.master")
    public static let startAtTitleScreen = Self("opensky.startAtTitleScreen")

    /// One volume per menu-flagged `SNCT`, keyed by its editor ID.
    public static func categoryVolume(_ editorID: String) -> Self {
        Self("audio.category.\(editorID)")
    }
}
