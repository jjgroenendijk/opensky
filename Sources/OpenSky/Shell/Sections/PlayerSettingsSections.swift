// World > Settings sections. Each lists its rows as a readout over a few buttons.

import AppKit
import OpenSkyGameData
import OpenSkyMenus

final class PlayerSettingsTableSection: MenuButtonSection {
    weak var provider: (any PlayerSettingsControlProviding)?

    init() {
        super.init(statsIdentifier: "PlayerSettingsStatsLabel")
    }

    override var sectionTitle: String {
        "Player Settings"
    }

    override var sectionIdentifier: String {
        "playerSettings"
    }

    override func makeActions() -> [[Action]] {
        [[
            Action(
                title: "Previous Group", identifier: "PlayerSettingsPreviousGroupControl",
                toolTip: "Show the previous settings group."
            ) { [weak self] in self?.provider?.selectPlayerSettingsGroup(offset: -1) },
            Action(
                title: "Next Group", identifier: "PlayerSettingsNextGroupControl",
                toolTip: "Show the next settings group."
            ) { [weak self] in self?.provider?.selectPlayerSettingsGroup(offset: 1) },
            Action(
                title: "Reset Group", identifier: "PlayerSettingsResetGroupControl",
                toolTip: "Put every setting in this group back to its default."
            ) { [weak self] in self?.provider?.resetPlayerSettingsGroup() }
        ]]
    }

    override func isEnabled(_ identifier: String) -> Bool {
        provider != nil
    }

    override func readoutText() -> String {
        guard let snapshot = provider?.playerSettingsSnapshot else {
            return "Settings: unavailable"
        }
        return Self.readout(for: snapshot)
    }

    nonisolated static func readout(for snapshot: PlayerSettingsSnapshot) -> String {
        let rows = snapshot.rows.map { row in
            let applied = row.isApplied ? "" : ", stored only"
            let changed = row.isChanged ? " *" : ""
            return "\(row.title): \(row.value) (default \(row.defaultValue)\(applied))\(changed)"
        }
        return (["Group: \(snapshot.group.title)"] + rows).joined(separator: "\n")
    }
}

final class KeyBindingsSection: MenuButtonSection {
    weak var provider: (any PlayerSettingsControlProviding)?

    init() {
        super.init(statsIdentifier: "KeyBindingsStatsLabel")
    }

    override var sectionTitle: String {
        "Key Bindings"
    }

    override var sectionIdentifier: String {
        "keyBindings"
    }

    override var isOverridden: Bool {
        Self.isOverridden(provider: provider)
    }

    override func resetToDefaults() {
        Self.resetToDefaults(provider: provider)
    }

    /// Only a key remap counts. Setting values are the player's own choice, and
    /// Reset Group puts them back.
    static func isOverridden(provider: (any PlayerSettingsControlProviding)?) -> Bool {
        provider?.playerSettingsSnapshot.bindings.contains(where: \.isOverride) == true
    }

    static func resetToDefaults(provider: (any PlayerSettingsControlProviding)?) {
        provider?.resetKeyBindings()
    }

    override func makeActions() -> [[Action]] {
        [[
            Action(
                title: "Reset Keys", identifier: "KeyBindingsResetControl",
                toolTip: "Drop every key remap and use the install's keys."
            ) { [weak self] in self?.provider?.resetKeyBindings() }
        ]]
    }

    override func isEnabled(_ identifier: String) -> Bool {
        provider != nil
    }

    override func readoutText() -> String {
        guard let snapshot = provider?.playerSettingsSnapshot else { return "Keys: unavailable" }
        return Self.readout(for: snapshot)
    }

    nonisolated static func readout(for snapshot: PlayerSettingsSnapshot) -> String {
        let rows = snapshot.bindings.map { row in
            "\(row.event): \(row.key)" + (row.isOverride ? " (remapped)" : "")
        }
        let conflicts = snapshot.conflicts.isEmpty
            ? ["Conflicts: none"] : snapshot.conflicts.map { "Conflict: \($0)" }
        return (rows + conflicts).joined(separator: "\n")
    }
}

final class DifficultySection: MenuButtonSection {
    weak var provider: (any PlayerSettingsControlProviding)?

    init() {
        super.init(statsIdentifier: "DifficultyStatsLabel")
    }

    override var sectionTitle: String {
        "Difficulty"
    }

    override var sectionIdentifier: String {
        "difficulty"
    }

    override func makeActions() -> [[Action]] {
        [[
            Action(
                title: "Easier", identifier: "DifficultyEasierControl",
                toolTip: "Pick the next easier difficulty."
            ) { [weak self] in self?.provider?.stepDifficulty(by: -1) },
            Action(
                title: "Harder", identifier: "DifficultyHarderControl",
                toolTip: "Pick the next harder difficulty."
            ) { [weak self] in self?.provider?.stepDifficulty(by: 1) }
        ]]
    }

    override func isEnabled(_ identifier: String) -> Bool {
        provider != nil
    }

    override func readoutText() -> String {
        guard let snapshot = provider?.playerSettingsSnapshot else {
            return "Difficulty: unavailable"
        }
        return Self.readout(for: snapshot)
    }

    nonisolated static func readout(for snapshot: PlayerSettingsSnapshot) -> String {
        (["Difficulty: \(snapshot.difficulty)"] + snapshot.multipliers).joined(separator: "\n")
    }
}
