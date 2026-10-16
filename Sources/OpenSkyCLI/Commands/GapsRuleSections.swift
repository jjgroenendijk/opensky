// The `gaps` sections over game rules the engine runs: Papyrus events, game settings,
// and AI package procedures.

import Foundation
import OpenSkyCombatInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyPerceptionInterface
import OpenSkyScripting
import OpenSkyWorld

extension GapsGatherer {
    func events() -> GapSection {
        let loader = PexScriptLoader(fileSystem: fileSystem)
        let files = loader.scriptPaths().compactMap { try? loader.load($0) }
        let census = PapyrusEventCensus(files: files)
        return GapSection(
            title: "Papyrus events", unit: "events", counts: census.handlers,
            handled: PapyrusEventCensus.isSent, usesUnit: "scripts that handle it",
            notes: [
                "\(census.declaredEventCount) events the engine classes declare, "
                    + "\(census.handlers.uses.count) handled by some script"
            ]
        )
    }

    func settings() throws -> GapSection {
        var defined = GapCounts()
        for plugin in try requirePlugins().plugins {
            let store = GameSettingStore(plugins: [(name: plugin.name, file: plugin.file)])
            for resolved in store.values.values {
                defined.add(resolved.setting.editorID)
            }
        }
        let read = Self.settingsRead(plugins: plugins)
        let unused = defined.uses.keys.filter { GameSettingsUnused.reason(for: $0) != nil }
        return GapSection(
            title: "Game settings", unit: "settings", counts: defined,
            handled: {
                read.contains($0.lowercased()) || $0.hasPrefix(MenuRecordData.statsPrefix)
                    || MenuRecordData.isMenuText($0) || GameSettingsUnused.reason(for: $0) != nil
            },
            usesUnit: "plugins that set it",
            notes: [
                "done means a settings reader asks for it; \(read.count) names asked for",
                "\(unused.count) more are done: the game never uses them (GameSettingsUnused)"
            ]
        )
    }

    func packages() -> [GapSection] {
        let census = PackageProcedureCensus(store: PackageStore(loadOrder: plugins))
        return [
            GapSection(
                title: "AI package procedures", unit: "procedures", counts: census.procedures,
                handled: PackageProcedureCensus.isRunnable, usesUnit: "packages",
                notes: [
                    "\(census.packageCount) packages; a package runs one procedure of its tree"
                ]
            ),
            GapSection(
                title: "AI packages that do not resolve", unit: "failure kinds",
                failures: census.failures, usesUnit: "packages"
            )
        ]
    }

    /// Runs every settings reader against a store that logs what it asks for. A new
    /// reader goes here; the `game_setting_reader` lint rule names the files.
    static func settingsRead(plugins: LoadOrderPlugins) -> Set<String> {
        var store = GameSettingStore(plugins: plugins.plugins.map { ($0.name, $0.file) })
        let log = GameSettingReadLog()
        store.readLog = log
        _ = ArcherySettings.resolve(store: store)
        _ = CombatSettings.resolve(store: store)
        _ = DifficultySettings.resolve(store: store)
        _ = ActorValueLevelSettings.resolve(store: store)
        _ = BarterPricing.resolve(store: store)
        _ = CharacterLevelSettings.resolve(store: store)
        _ = MenuMapSettings(store: store)
        _ = SkillAdvancementSettings.resolve(store: store)
        _ = SocialSettings.resolve(store: store)
        _ = SpeechCheckSettings.resolve(store: store)
        _ = HarvestRegrowth.resolve(store: store)
        _ = LockpickingSettings.resolve(store: store)
        _ = DetectionSettings.resolve(store: store)
        _ = PlayerMovementConfiguration.resolve(store: store)
        _ = RegenerationSettings.resolve(store: store)
        return log.editorIDs
    }
}
