// The game's own INI values become the catalog defaults, so a stored OpenSky value
// sits over what the player set in the game. OpenSky never writes the INI files.
// The keys were read from the install's Skyrim/SkyrimPrefs.ini.

import Foundation

nonisolated extension PlayerSettingsCatalog {
    /// `SkyrimPrefs.ini` in the install's `Skyrim` folder; the game's
    /// Documents copy is not read, because OpenSky has no Documents folder of its own.
    public static func iniCandidates(installURL: URL) -> [(name: String, url: URL)] {
        let profile = installURL.appending(path: "Skyrim", directoryHint: .isDirectory)
        return [("Skyrim/SkyrimPrefs.ini", profile.appending(path: "SkyrimPrefs.ini"))]
    }

    /// `fMouseHeadingSensitivity` at the slider's middle. OpenSky's mapping: the
    /// install's default 0.0125 sits at 0.5.
    public static let mouseSensitivityAtMiddle = 0.0125

    /// A copy whose defaults come from `ini` where it has a valid value.
    public func applyingINIDefaults(_ ini: INISettings) -> PlayerSettingsCatalog {
        var overrides: [PlayerSettingID: Double] = [:]
        for entry in Self.booleanKeys {
            if
                let raw = ini.string(section: entry.section, key: entry.key)?.value,
                let value = Int(raw)
            {
                overrides[entry.id] = value == 0 ? 0 : 1
            }
        }
        if let opacity = ini.float(section: "MAIN", key: "fHUDOpacity")?.value {
            overrides[.hudOpacity] = Double(opacity)
        }
        if
            let raw = ini.string(section: "GamePlay", key: "iDifficulty")?.value,
            let level = Int(raw)
        {
            overrides[.difficulty] = Double(level)
        }
        if let volume = ini.float(section: "AudioMenu", key: "fAudioMasterVolume")?.value {
            overrides[.masterVolume] = Double(volume)
        }
        if let heading = ini.float(section: "Controls", key: "fMouseHeadingSensitivity")?.value {
            overrides[.lookSensitivity] = Double(heading) / Self.mouseSensitivityAtMiddle / 2
        }
        if let pause = ini.string(section: "MAIN", key: "bSaveOnPause")?.value {
            let minutes = ini.float(section: "SaveGame", key: "fAutosaveEveryXMins")?.value ?? 15
            overrides[.saveOnPause] = pause == "0" ? 6 : Self.saveOnPauseIndex(minutes: minutes)
        }
        return PlayerSettingsCatalog(definitions: definitions.map { definition in
            guard
                let raw = overrides[definition.id],
                let value = definition.clamp(raw)
            else { return definition }
            return PlayerSettingDefinition(
                id: definition.id, group: definition.group, kind: definition.kind,
                title: definition.title, defaultValue: value, isApplied: definition.isApplied
            )
        })
    }

    private struct INIKey {
        let id: PlayerSettingID
        let section: String
        let key: String
    }

    private static let booleanKeys: [INIKey] = [
        INIKey(id: .crosshair, section: "MAIN", key: "bCrosshairEnabled"),
        INIKey(id: .saveOnTravel, section: "MAIN", key: "bSaveOnTravel"),
        INIKey(id: .saveOnWait, section: "MAIN", key: "bSaveOnWait"),
        INIKey(id: .saveOnRest, section: "MAIN", key: "bSaveOnRest"),
        INIKey(id: .dialogueSubtitles, section: "Interface", key: "bDialogueSubtitles"),
        INIKey(id: .generalSubtitles, section: "Interface", key: "bGeneralSubtitles"),
        INIKey(id: .compass, section: "Interface", key: "bShowCompass"),
        INIKey(id: .floatingMarkers, section: "GamePlay", key: "bShowFloatingQuestMarkers"),
        INIKey(id: .invertLook, section: "Controls", key: "bInvertYValues")
    ]

    /// The stepper option nearest a minute count: 5, 10, 15, 30, 45, or 60.
    public static func saveOnPauseIndex(minutes: Float) -> Double {
        let steps: [Float] = [5, 10, 15, 30, 45, 60]
        let nearest = steps.indices.min { abs(steps[$0] - minutes) < abs(steps[$1] - minutes) }
        return Double(nearest ?? 2)
    }
}
