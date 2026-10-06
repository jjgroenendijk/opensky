// World > Settings: stable ids, buttons that reach the provider, and the readouts.

import AppKit
@testable import OpenSky
@testable import OpenSkyGameData
@testable import OpenSkyMenus
import Testing

struct PlayerSettingsPanelTests {
    @MainActor
    private func send(_ control: NSControl) {
        control.sendAction(control.action, to: control.target)
    }

    @Test @MainActor
    func panelPinsIdsAndDrivesTheSettings() {
        let provider = FakeWorldProviders()
        let panel = PlayerSettingsPanelViewController()
        panel.provider = provider
        panel.loadViewIfNeeded()
        #expect(panel.settingsSection.sectionIdentifier == "playerSettings")
        #expect(panel.bindingsSection.sectionIdentifier == "keyBindings")
        #expect(panel.difficultySection.sectionIdentifier == "difficulty")
        #expect(panel.settingsSection.buttons.map { $0.accessibilityIdentifier() } == [
            "PlayerSettingsPreviousGroupControl", "PlayerSettingsNextGroupControl",
            "PlayerSettingsResetGroupControl"
        ])
        #expect(panel.bindingsSection.buttons.map { $0.accessibilityIdentifier() } == [
            "KeyBindingsResetControl"
        ])
        #expect(panel.difficultySection.buttons.map { $0.accessibilityIdentifier() } == [
            "DifficultyEasierControl", "DifficultyHarderControl"
        ])
        let buttons = panel.settingsSection.buttons + panel.bindingsSection.buttons
            + panel.difficultySection.buttons
        buttons.forEach(send)
        #expect(provider.menuCalls.calls == [
            "settings.group(-1)", "settings.group(1)", "settings.resetGroup",
            "settings.resetKeys", "settings.difficulty(-1)", "settings.difficulty(1)"
        ])
    }

    @Test
    func readoutsListValuesDefaultsAndConflicts() {
        let snapshot = PlayerSettingsSnapshot(
            group: .gameplay,
            rows: [
                PlayerSettingRow(
                    title: "Invert Y",
                    value: "on",
                    defaultValue: "off",
                    isApplied: true
                ),
                PlayerSettingRow(
                    title: "Save on Rest",
                    value: "on",
                    defaultValue: "on",
                    isApplied: false
                )
            ],
            bindings: [KeyBindingRow(
                event: "Jump",
                context: .gameplay,
                key: "J",
                isOverride: true
            )],
            conflicts: ["J: Jump, Journal"], difficulty: "Master",
            multipliers: ["Damage dealt: 0.50"]
        )
        #expect(PlayerSettingsTableSection.readout(for: snapshot) == """
        Group: \(PlayerSettingGroup.gameplay.title)
        Invert Y: on (default off) *
        Save on Rest: on (default on, stored only)
        """)
        #expect(KeyBindingsSection
            .readout(for: snapshot) == "Jump: J (remapped)\nConflict: J: Jump, Journal")
        #expect(DifficultySection
            .readout(for: snapshot) == "Difficulty: Master\nDamage dealt: 0.50")
    }
}
