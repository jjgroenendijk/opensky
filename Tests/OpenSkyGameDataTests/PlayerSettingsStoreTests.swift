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
        first.replaceKeyBindings(["Main Gameplay|Forward": 0x48])
        #expect(changed == [.masterVolume, .keyBindingsChanged])

        let second = PlayerSettingsStore(persistence: disk)
        #expect(second.value(.masterVolume) == 0.25)
        #expect(second.model.keyBindings == ["Main Gameplay|Forward": 0x48])
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
