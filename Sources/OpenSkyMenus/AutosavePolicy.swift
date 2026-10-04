// When the game saves by itself, and into which slot. The triggers follow the
// Gameplay settings. Save on Pause saves when the pause menu opens and the chosen
// minutes have passed since the last save. Autosaves rotate through a few slots.

import Foundation
import OpenSkyGameData

nonisolated public enum AutosaveTrigger: String, Equatable, Sendable {
    case rest, wait, travel, pause
}

public struct AutosavePolicy: Equatable {
    public static let slotPrefix = "Autosave"
    public static let quicksaveSlot = "Quicksave"
    public static let slotCount = 3

    public static func slot(_ number: Int) -> String {
        "\(slotPrefix)\(number)"
    }

    public static let slots = (1 ... slotCount).map { slot($0) }

    /// Minutes for each Save on Pause option, in the menu's order; nil is Disabled.
    /// UESP "Skyrim:Saving" describes the option.
    public static let timerMinutes: [Double?] = [5, 10, 15, 30, 45, 60, nil]

    public init() {}

    public func isEnabled(_ trigger: AutosaveTrigger, settings: PlayerSettingsStore) -> Bool {
        switch trigger {
        case .rest: settings.bool(.saveOnRest)
        case .wait: settings.bool(.saveOnWait)
        case .travel: settings.bool(.saveOnTravel)
        case .pause: pauseInterval(settings: settings) != nil
        }
    }

    /// True when opening the pause menu should save now.
    public func shouldSaveOnPause(
        settings: PlayerSettingsStore, lastSave: Date?, now: Date
    ) -> Bool {
        guard let interval = pauseInterval(settings: settings) else { return false }
        guard let lastSave else { return true }
        return now.timeIntervalSince(lastSave) >= interval
    }

    /// Seconds that must pass between pause saves, or nil when Disabled.
    public func pauseInterval(settings: PlayerSettingsStore) -> Double? {
        let index = Int(settings.value(.saveOnPause))
        guard Self.timerMinutes.indices.contains(index), let minutes = Self.timerMinutes[index]
        else { return nil }
        return minutes * 60
    }

    /// The autosave slot to write next: an unused one, else the oldest.
    public func nextSlot(saved: [String: Date]) -> String {
        if let free = Self.slots.first(where: { saved[$0] == nil }) {
            return free
        }
        return Self.slots.min { (saved[$0] ?? .distantPast) < (saved[$1] ?? .distantPast) }
            ?? Self.slot(1)
    }
}
