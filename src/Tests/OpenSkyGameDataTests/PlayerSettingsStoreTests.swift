// The settings store: values and key bindings survive a restart, a bad file
// starts from defaults, and the install's INI sets the defaults.

import Foundation
@testable import OpenSkyGameData
import Testing

private final class MemoryPersistence: PlayerSettingsPersistence {
    var data: Data?

    func loadSettings() throws -> Data? {
        data
    }

    func saveSettings(_ data: Data) throws {
        self.data = data
    }
}

@MainActor
struct PlayerSettingsStoreTests {
    @Test func valuesAndBindingsSurviveARestart() {
        let disk = MemoryPersistence()
        let first = PlayerSettingsStore(persistence: disk)
        var changed: [PlayerSettingID] = []
        first.observe { changed.append($0) }
        first.set(.masterVolume, to: 0.25)
        // A mouse button is 256 and up, a gamepad button up to 0x8000.
        let bindings = [
            "Main Gameplay|Forward": 0x48, "Main Gameplay|Left Attack/Block": 0x101,
            "Gamepad|Main Gameplay|Jump": 0x8000
        ]
        first.replaceKeyBindings(bindings)
        #expect(changed == [.masterVolume, .keyBindingsChanged])

        let second = PlayerSettingsStore(persistence: disk)
        #expect(second.value(.masterVolume) == 0.25)
        #expect(second.model.keyBindings == bindings)
    }

    /// The player is told once: the whole file, or only its controls.
    @Test func aFileThatCannotBeReadIsReportedOnce() {
        let disk = MemoryPersistence()
        disk.data = Data("not json".utf8)
        let broken = PlayerSettingsStore(persistence: disk)
        #expect(broken.takeLoadFailure() == .settings)
        #expect(broken.takeLoadFailure() == nil)
        disk.data = Data(#"{"schema": 3, "keyBindings": {"Main Gameplay|Jump": "space"}}"#.utf8)
        #expect(PlayerSettingsStore(persistence: disk).takeLoadFailure() == .controls)
        disk.data = Data(#"{"schema": 3, "keyBindings": {"Main Gameplay|Jump": 57}}"#.utf8)
        #expect(PlayerSettingsStore(persistence: disk).takeLoadFailure() == nil)
    }

    @Test func aBenchmarkCopyTakesOverridesAndNeverSaves() {
        let disk = MemoryPersistence()
        let saved = PlayerSettingsStore(persistence: disk)
        saved.set(.masterVolume, to: 0.5)
        let before = disk.data
        let copy = PlayerSettingsStore(
            copying: saved,
            overrides: [.gpuCulling: 0, .masterVolume: 0.25]
        )
        #expect(copy.value(.gpuCulling) == 0)
        #expect(copy.value(.masterVolume) == 0.25)
        copy.set(.masterVolume, to: 0.75)
        #expect(disk.data == before)
        #expect(saved.value(.masterVolume) == 0.5)
    }

    @Test func aTextValueSurvivesARestartAndUnknownTextIsIgnored() {
        let disk = MemoryPersistence()
        let first = PlayerSettingsStore(persistence: disk)
        first.setText(.assetOptimisationFolder, to: "/Volumes/Fast/Cache")
        first.setText(PlayerSettingID("unknown.text"), to: "x")
        let second = PlayerSettingsStore(persistence: disk)
        #expect(second.text(.assetOptimisationFolder) == "/Volumes/Fast/Cache")
        #expect(second.text(PlayerSettingID("unknown.text")) == nil)
        second.setText(.assetOptimisationFolder, to: "")
        #expect(PlayerSettingsStore(persistence: disk).text(.assetOptimisationFolder) == nil)
    }

    @Test func anUnreadableFileStartsFromDefaults() {
        let disk = MemoryPersistence()
        disk.data = Data("not json".utf8)
        let store = PlayerSettingsStore(persistence: disk)
        #expect(store.value(.masterVolume) == store.catalog.definition(.masterVolume)?.defaultValue)
    }

    @Test func theINISetsTheDefaultsAndABadValueIsIgnored() {
        let ini = INISettings(sources: [INISettingsSource(
            name: "Skyrim.ini",
            file: INIFile(data: Data("[MAIN]\nbCrosshairEnabled=0\n[Interface]\nbShowCompass=x"
                    .utf8))
        )])
        let catalog = PlayerSettingsCatalog.vanilla.applyingINIDefaults(ini)
        #expect(catalog.definition(.crosshair)?.defaultValue == 0)
        #expect(catalog.definition(.compass)?.defaultValue
            == PlayerSettingsCatalog.vanilla.definition(.compass)?.defaultValue)
    }
}
