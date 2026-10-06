// `FakeWorldProviders`' settings seam: one group, one binding, and the calls kept.

import AppKit
@testable import OpenSkyGameData
@testable import OpenSkyMenus

extension FakeWorldProviders {
    var playerSettingsSnapshot: PlayerSettingsSnapshot {
        PlayerSettingsSnapshot(
            group: .gameplay,
            rows: [PlayerSettingRow(
                title: "Invert Y", value: "off", defaultValue: "off", isApplied: true
            )],
            bindings: [KeyBindingRow(
                event: "Jump", context: .gameplay, key: "Space", isOverride: false
            )],
            conflicts: [], difficulty: "Adept", multipliers: ["Damage dealt: 1.00 (UESP)"]
        )
    }

    func selectPlayerSettingsGroup(offset: Int) {
        menuCalls.calls.append("settings.group(\(offset))")
    }

    func resetPlayerSettingsGroup() {
        menuCalls.calls.append("settings.resetGroup")
    }

    func resetKeyBindings() {
        menuCalls.calls.append("settings.resetKeys")
    }

    func stepDifficulty(by offset: Int) {
        menuCalls.calls.append("settings.difficulty(\(offset))")
    }
}
