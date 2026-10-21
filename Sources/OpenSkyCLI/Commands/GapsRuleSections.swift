// The `gaps` sections over game rules the engine runs: Papyrus events, game settings,
// and AI package procedures.

import Foundation
import OpenSkyAIPackages
import OpenSkyCombatInterface
import OpenSkyCrimeInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMagic
import OpenSkyPerceptionInterface
import OpenSkyPlayer
import OpenSkyScripting
import OpenSkyWorldState

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
        _ = WeaponDamageSettings.resolve(store: store)
        _ = PowerAttackSettings.resolve(store: store)
        _ = MeleeSkillUseSettings.resolve(store: store)
        _ = ArrowSettings.resolve(store: store)
        _ = TrainingSettings.resolve(store: store)
        _ = CraftingSkillUseSettings.resolve(store: store)
        _ = CalendarTexts.resolve(store: store)
        _ = TopicSubtypeTexts.resolve(store: store)
        _ = MagicTexts.resolve(store: store)
        _ = CrimeTexts.resolve(store: store)
        _ = InventoryMenuTexts.resolve(store: store)
        _ = ProgressionTexts.resolve(store: store)
        _ = ItemNoticeTexts.resolve(store: store)
        _ = SaveTexts.resolve(store: store)
        _ = TradeTexts.resolve(store: store)
        _ = SoulTexts.resolve(store: store)
        _ = SoulTrapSettings.resolve(store: store)
        _ = ShoutSettings.resolve(store: store)
        _ = SpellCostSettings.resolve(store: store)
        _ = DifficultySettings.resolve(store: store)
        _ = ActorValueLevelSettings.resolve(store: store)
        _ = BarterPricing.resolve(store: store)
        _ = CharacterLevelSettings.resolve(store: store)
        _ = MenuMapSettings(store: store)
        _ = SkillAdvancementSettings.resolve(store: store)
        _ = SocialSettings.resolve(store: store)
        _ = SpeechCheckSettings.resolve(store: store)
        _ = PickpocketSettings.resolve(store: store)
        _ = AlchemySettings.resolve(store: store)
        _ = LockpickingSettings.resolve(store: store)
        _ = LockTexts.resolve(store: store)
        _ = TemperingTexts.resolve(store: store)
        _ = DetectionSettings.resolve(store: store)
        _ = PlayerMovementConfiguration.resolve(store: store)
        _ = RegenerationSettings.resolve(store: store)
        _ = StaminaSettings.resolve(store: store)
        _ = BreathSettings.resolve(store: store)
        _ = CellResetSettings.resolve(store: store)
        _ = CrimeSettings.resolve(store: store)
        _ = VendorRestockSettings.resolve(store: store)
        _ = StealthPointSettings.resolve(store: store)
        _ = EnchantedValueSettings.resolve(store: store)
        return log.editorIDs
    }
}
