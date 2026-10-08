// `actor-values`: prints the resolved race, class and level beside the derived
// maximums, so an unexpected number can be traced to its record. `--race`
// reports one RACE's starting attributes and regen rates instead.
// Derivation and resolution live in their modules; this file parses and prints.

import Foundation
import OpenSkyCLIArguments
import OpenSkyFormatsESM
import OpenSkyGameData

enum ActorValueCommand {
    static func run(context: CLIContext, arguments: ActorValuesArguments) throws {
        let npc = arguments.npc
        let race = arguments.race
        let playerLevel = try int(arguments.playerLevel, name: "--player-level") ?? 1

        let file = try context.loadSkyrimESM()
        let localized = file.isLocalized
        let settings = ActorValueLevelSettings.resolve(
            store: GameSettingLoader.load(root: context.root, baseFile: file)
        )
        print("[INFO] iAVDhmsLevelUp = \(settings.pointsPerLevel), "
            + "fNPCHealthLevelBonus = \(settings.healthBonusPerLevel), "
            + "iAVDSkillsLevelUp = \(settings.skillPointsPerLevel)")
        let resolver = ActorValueResolver.build(
            from: file,
            localized: localized,
            pluginName: context.skyrimESMName,
            classes: CharacterClassStoreLoader.load(root: context.root, baseFile: file),
            settings: settings,
            playerLevel: PlayerLevelSource(playerLevel)
        )
        if let race {
            try reportRace(race, resolver: resolver)
            return
        }
        guard let npc else {
            throw CLIError.usage("actor-values expects --npc or --race")
        }
        try reportActor(npc, resolver: resolver)
    }

    // MARK: - Reporting

    private static func reportActor(_ key: String, resolver: ActorValueResolver) throws {
        let base = try baseFormID(key, resolver: resolver)
        let editorID = resolver.templates.actors[base.rawValue]?.editorID ?? "?"
        print("NPC_ \(base) \"\(editorID)\"")
        let resolved: ResolvedActorValues
        do {
            resolved = try resolver.resolve(base: base)
        } catch {
            throw CLIError.failure("unresolved: \(String(describing: error))")
        }
        let raceName = resolved.race
            .flatMap { resolver.races[$0.rawValue]?.editorID }
        let className = resolver.characterClass(resolved.characterClass)?.editorID
        print("  race \(describe(resolved.race)) \(raceName ?? "—")"
            + "; class \(describe(resolved.characterClass)) \(className ?? "—")"
            + "; level \(resolved.level)"
            + "; auto-calc \(resolved.autoCalculatesStats)")
        let stats = try? resolver.templates.resolveStats(base: base)
        if let stats {
            printInputs(stats, resolver: resolver)
        }
        print("  derived  " + triple(resolved.maximums))
        if let baked = resolved.bakedValues {
            print("  DNAM     " + triple(baked)
                + (resolved.autoCalculatesStats
                    ? "" : " [WARNING] auto-calc off: DNAM is not authoritative"))
        }
        print("  regen %/s " + triple(resolved.regenPercentPerSecond))
        printGeneral(resolved.generalBaseValues)
    }

    /// The non-primary actor values this actor's records author, in table order
    /// with their vanilla names. Unauthored indexes are left off rather than
    /// printed as a number nothing authored.
    private static func printGeneral(_ values: [Int32: Float]) {
        guard !values.isEmpty else { return }
        print("  record-authored actor values (\(values.count)):")
        for index in values.keys.sorted() {
            guard let value = values[index] else { continue }
            print(String(
                format: "    %3d %-24@ %.2f",
                index,
                ActorValueIdentity.description(of: index) as NSString,
                value
            ))
        }
    }

    /// The three inputs behind the derived triple, so an unexpected number can
    /// be traced to the record that authored it.
    private static func printInputs(
        _ stats: ResolvedActorStats,
        resolver: ActorValueResolver
    ) {
        let value = stats.stats.value
        print("  offsets health \(value.healthOffset), magicka \(value.magickaOffset), "
            + "stamina \(value.staminaOffset)")
        print("  stats from \(stats.stats.source); stat race from \(stats.statsRace.source); "
            + "trait race from \(stats.race.source)")
        if let weights = resolver.characterClass(value.characterClass)?.attributeWeights {
            print("  weights health \(weights.health), magicka \(weights.magicka), "
                + "stamina \(weights.stamina)")
        }
        if let raceStats = stats.statsRace.value.flatMap({ resolver.races[$0.rawValue] }) {
            print("  race base " + triple(ActorValues(
                health: raceStats.stats.startingHealth,
                magicka: raceStats.stats.startingMagicka,
                stamina: raceStats.stats.startingStamina
            )))
        }
    }

    private static func reportRace(_ key: String, resolver: ActorValueResolver) throws {
        let matches = resolver.races.values
            .filter { $0.editorID == key || String(format: "%08X", $0.formID.rawValue) == key }
            .sorted { $0.formID.rawValue < $1.formID.rawValue }
        guard let race = matches.first else {
            throw CLIError.failure("no RACE record matches \(key)")
        }
        let stats = race.stats
        print("RACE \(race.formID) \"\(race.editorID ?? "?")\"")
        print("  starting  " + triple(ActorValues(
            health: stats.startingHealth,
            magicka: stats.startingMagicka,
            stamina: stats.startingStamina
        )))
        print("  regen %/s " + triple(ActorValues(
            health: stats.healthRegenPercent,
            magicka: stats.magickaRegenPercent,
            stamina: stats.staminaRegenPercent
        )))
        print(String(
            format: "  carry weight %.2f, mass %.2f, unarmed damage %.2f",
            stats.baseCarryWeight,
            stats.baseMass,
            stats.unarmedDamage
        ))
        printGeneral(ActorValueDerivation.generalBaseValues(
            inputs: ActorValueInputs(race: stats)
        ))
    }

    // MARK: - Formatting

    private static func triple(_ values: ActorValues) -> String {
        String(
            format: "health %.2f, magicka %.2f, stamina %.2f",
            values.health,
            values.magicka,
            values.stamina
        )
    }

    private static func describe(_ id: FormID?) -> String {
        id.map { "\($0)" } ?? "none"
    }

    private static func baseFormID(
        _ key: String,
        resolver: ActorValueResolver
    ) throws -> FormID {
        if let raw = UInt32(key, radix: 16), resolver.templates.actors[raw] != nil {
            return FormID(raw)
        }
        if let match = resolver.templates.actors.values.first(where: { $0.editorID == key }) {
            return match.formID
        }
        throw CLIError.failure("no NPC_ record matches \(key)")
    }

    private static func int(_ value: String?, name: String) throws -> Int? {
        guard let value else { return nil }
        guard let parsed = Int(value), parsed >= 1 else {
            throw CLIError.usage("\(name) expects an integer >= 1")
        }
        return parsed
    }
}
