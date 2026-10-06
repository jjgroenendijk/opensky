// The sidebar's view of the player settings, the key bindings, and difficulty.

import Foundation
import OpenSkyGameData

nonisolated public struct PlayerSettingsSnapshot: Equatable, Sendable {
    public let group: PlayerSettingGroup
    public let rows: [PlayerSettingRow]
    public let bindings: [KeyBindingRow]
    public let conflicts: [String]
    public let difficulty: String
    /// One "Label: value" line per resolved multiplier of the chosen level.
    public let multipliers: [String]

    public init(
        group: PlayerSettingGroup, rows: [PlayerSettingRow], bindings: [KeyBindingRow],
        conflicts: [String], difficulty: String, multipliers: [String]
    ) {
        self.group = group
        self.rows = rows
        self.bindings = bindings
        self.conflicts = conflicts
        self.difficulty = difficulty
        self.multipliers = multipliers
    }
}

public protocol PlayerSettingsControlProviding: AnyObject {
    /// Gives keyboard focus back to the game view after a panel button.
    func refocusGameView()
    var playerSettingsSnapshot: PlayerSettingsSnapshot { get }
    func selectPlayerSettingsGroup(offset: Int)
    func resetPlayerSettingsGroup()
    func resetKeyBindings()
    func stepDifficulty(by offset: Int)
}

extension PlayerSettingsCoordinator {
    /// The snapshot for the inspected group. The multipliers come from combat,
    /// which this module does not import.
    public func snapshot(multipliers: [String]) -> PlayerSettingsSnapshot {
        let difficulty = store.catalog.definition(.difficulty).map {
            PlayerSettingsInspection.text(store.value(.difficulty), kind: $0.kind)
        } ?? "unknown"
        return PlayerSettingsSnapshot(
            group: inspectedGroup,
            rows: PlayerSettingsInspection.rows(store: store, group: inspectedGroup),
            bindings: PlayerSettingsInspection.bindingRows(bindings),
            conflicts: PlayerSettingsInspection.conflicts(bindings),
            difficulty: difficulty, multipliers: multipliers
        )
    }

    public func selectGroup(offset: Int) {
        let groups = PlayerSettingGroup.allCases
        let index = groups.firstIndex(of: inspectedGroup) ?? 0
        inspectedGroup = groups[(index + offset % groups.count + groups.count) % groups.count]
    }
}

/// Lets the app's provider object stand in for its `PlayerSettingsCoordinator`.
public protocol PlayerSettingsControlForwarding: PlayerSettingsControlProviding {
    var playerSettings: PlayerSettingsCoordinator { get }
    /// The resolved multipliers of the level the settings store holds now.
    var difficultyMultiplierLines: [String] { get }
}

extension PlayerSettingsControlForwarding {
    public var playerSettingsSnapshot: PlayerSettingsSnapshot {
        playerSettings.snapshot(multipliers: difficultyMultiplierLines)
    }

    public func selectPlayerSettingsGroup(offset: Int) {
        playerSettings.selectGroup(offset: offset)
    }

    public func resetPlayerSettingsGroup() {
        playerSettings.resetGroup(playerSettings.inspectedGroup)
    }

    public func resetKeyBindings() {
        playerSettings.resetBindings()
    }

    public func stepDifficulty(by offset: Int) {
        playerSettings.store.step(.difficulty, by: offset)
    }
}
