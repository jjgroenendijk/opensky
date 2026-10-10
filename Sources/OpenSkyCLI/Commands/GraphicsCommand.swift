// `graphics status|preset`: reads and writes the same settings file as the
// launcher's Graphics page. The preset values come from the install's INI files.

import Foundation
import OpenSkyGameData

enum GraphicsCommand {
    static func status(context: CLIContext) {
        let (store, presets) = load(context)
        print("preset\t\(presets.current(in: store)?.title ?? "Custom")")
        for option in GraphicsOptions.all {
            let state = option.unavailableReason == nil ? "applied" : "unavailable"
            let value = store.value(option.id).formatted(.number.grouping(.never))
            print("\(option.iniName)\t\(value)\t\(state)")
        }
    }

    static func preset(context: CLIContext, name: String) throws {
        let (store, presets) = load(context)
        guard let preset = GraphicsPreset.allCases.first(where: { $0.title.lowercased() == name })
        else {
            throw CLIError.usage("preset is low, medium, high, or ultra")
        }
        guard presets.files[preset] != nil else {
            throw CLIError.failure("\(preset.fileName) is not in the game folder")
        }
        presets.apply(preset, to: store)
        print("preset\t\(preset.title)")
    }

    private static func load(_ context: CLIContext) -> (PlayerSettingsStore, GraphicsPresetFiles) {
        let install = context.root.installURL
        let catalog = PlayerSettingsCatalog.vanilla.applyingINIDefaults(INISettings.load(
            candidates: TerrainLODSettings.iniCandidates(installURL: install)
        ))
        let store = PlayerSettingsStore(
            catalog: catalog,
            persistence: try? PlayerSettingsFile.defaultFile()
        )
        return (store, GraphicsPresetFiles.load(installURL: install))
    }
}
