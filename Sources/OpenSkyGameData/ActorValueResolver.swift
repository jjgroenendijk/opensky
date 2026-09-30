// Plugin-side seam of the actor-value subsystem: turns an NPC_ FormID into the
// derived base values, walking the template chain and the RACE and CLAS records.
// Immutable and record-only, like `InventoryBaselineResolver`; the runtime asks
// it for baselines. See docs/engine/actor-values.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

/// Why an actor's values could not be derived.
///
/// Deliberately few. A missing race or class is *not* an error — it degrades to
/// zero starting attributes and zero class weights, which is what a record that
/// names neither should produce. Only a chain that cannot be walked at all
/// fails, and that failure already has a type.
nonisolated public enum ActorValueResolveError: Error, Equatable {
    /// The template chain could not be walked; carries the underlying failure.
    case unresolvedChain(ActorResolveError)
}

/// One actor's derived baseline plus the records it came from, so an inspector
/// can say *why* a number is what it is rather than only what it is.
nonisolated public struct ResolvedActorValues: Equatable, Sendable {
    /// Base maximums: what `ActorValueState` starts full at.
    public let maximums: ActorValues
    /// Percent of each maximum restored per second, from the race.
    public let regenPercentPerSecond: ActorValues
    /// Base values for the non-primary actor values this actor's records author, by
    /// vanilla table index. An absent index reads
    /// `ActorValueIdentity.defaultValue(at:)`.
    public let generalBaseValues: [Int32: Float]
    /// The level the derivation used.
    public let level: Int
    /// RACE the starting attributes came from, nil when the chain names none.
    ///
    /// This is the *stats*-resolved race, not the traits-resolved one the
    /// renderer skins the actor with; see `ResolvedActorStats.statsRace`.
    public let race: FormID?
    /// CLAS the attribute weights came from, nil when the chain names none.
    public let characterClass: FormID?
    /// NPC_ that supplied the stat words, which is where an unexpected offset
    /// is actually authored.
    public let statsSource: FormID
    /// Whether the per-level spread applied at all.
    public let autoCalculatesStats: Bool
    /// Whether the level was scaled against the player's.
    public let usesPlayerLevelMultiplier: Bool
    /// DNAM's baked attributes, when the record carried them. Never an input —
    /// see `ActorBase.Stats.bakedHealth`.
    public let bakedValues: ActorValues?
}

/// Derives actor values from pre-built single-plugin record indexes, the same
/// raw-`UInt32` keying `ActorTemplateResolver` and `ActorVisualResolver` use.
nonisolated public struct ActorValueResolver: Sendable {
    public let templates: ActorTemplateResolver
    public let races: [UInt32: Race]
    /// Load-order-wide CLAS lookup. The NPC_ plugin travels beside it, because a
    /// class link resolves relative to the plugin carrying it.
    public let classes: CharacterClassStore
    /// Plugin the NPC_ and RACE indexes were built from, which is what a CLAS
    /// link in one of those records resolves against.
    public let pluginName: String
    public let settings: ActorValueLevelSettings
    /// Where the level a `PC Level Mult` actor scales against is published. Shared by
    /// reference, so a level-up applies on the next read. Without progression it
    /// stays 1.
    public let playerLevelSource: PlayerLevelSource
    private let raceSkips: SkippedRecords

    public var skippedRecords: SkippedRecords {
        templates.skippedRecords.merging(raceSkips).merging(classes.skippedRecords)
    }

    /// The level as of right now.
    public var playerLevel: Int {
        playerLevelSource.level
    }

    public init(
        templates: ActorTemplateResolver,
        raceSkips: SkippedRecords = SkippedRecords(),
        races: [UInt32: Race],
        classes: CharacterClassStore = CharacterClassStore(),
        pluginName: String = "",
        settings: ActorValueLevelSettings = .documentedDefaults,
        playerLevel: PlayerLevelSource = PlayerLevelSource()
    ) {
        self.templates = templates
        self.raceSkips = raceSkips
        self.races = races
        self.classes = classes
        self.pluginName = pluginName
        self.settings = settings
        playerLevelSource = playerLevel
    }

    /// Builds every index this resolver needs from one plugin file. `settings` and
    /// `classes` are passed in, so a caller does not pay for a second load-order walk
    /// and a patch plugin's CLAS override is seen.
    public static func build(
        from file: ESMFile,
        localized: Bool,
        pluginName: String,
        classes: CharacterClassStore? = nil,
        settings: ActorValueLevelSettings = .documentedDefaults,
        playerLevel: PlayerLevelSource = PlayerLevelSource()
    ) -> ActorValueResolver {
        var races: [UInt32: Race] = [:]
        var skipped = SkippedRecords()
        if let top = file.topGroup(of: "RACE") {
            for case let .record(record) in skipped.children(of: top) {
                guard record.type == "RACE", !record.isDeleted else { continue }
                races[record.formID] = skipped.decode(record) {
                    try Race(record: $0, localized: localized)
                }
            }
        }
        return ActorValueResolver(
            templates: ActorTemplateResolver.build(from: file, localized: localized),
            raceSkips: skipped,
            races: races,
            classes: classes ?? CharacterClassStore(file: file, pluginName: pluginName),
            pluginName: pluginName,
            settings: settings,
            playerLevel: playerLevel
        )
    }

    /// The class one record names, resolved through the load order.
    ///
    /// The one place a caller outside this type turns a CLAS link into a
    /// record, so nothing has to know which plugin the link resolves against.
    public func characterClass(_ id: FormID?) -> CharacterClass? {
        classes.resolve(id, fromPlugin: pluginName)?.characterClass
    }

    /// The full derived baseline for one NPC_.
    public func resolve(base: FormID) throws -> ResolvedActorValues {
        let resolved = try resolveStats(base: base)
        let gathered = inputs(from: resolved)
        let stats = resolved.stats.value
        // Read once: the three derivations below must agree about the level,
        // and a level-up landing between two of them would produce a baseline
        // whose maximums and reported level disagree.
        let currentPlayerLevel = playerLevel
        return ResolvedActorValues(
            maximums: ActorValueDerivation.baseValues(
                inputs: gathered,
                settings: settings,
                playerLevel: currentPlayerLevel
            ),
            regenPercentPerSecond: ActorValues(
                health: gathered.race.healthRegenPercent,
                magicka: gathered.race.magickaRegenPercent,
                stamina: gathered.race.staminaRegenPercent
            ),
            generalBaseValues: ActorValueDerivation.generalBaseValues(
                inputs: gathered,
                settings: settings,
                playerLevel: currentPlayerLevel
            ),
            level: ActorValueDerivation.level(inputs: gathered, playerLevel: currentPlayerLevel),
            race: resolved.statsRace.value,
            characterClass: stats.characterClass,
            statsSource: resolved.stats.source,
            autoCalculatesStats: resolved.autoCalculatesStats.value,
            usesPlayerLevelMultiplier: resolved.usesPlayerLevelMultiplier.value,
            bakedValues: bakedValues(of: stats)
        )
    }

    // MARK: - Private

    private func resolveStats(base: FormID) throws -> ResolvedActorStats {
        do {
            return try templates.resolveStats(base: base)
        } catch let error as ActorResolveError {
            throw ActorValueResolveError.unresolvedChain(error)
        }
    }

    private func inputs(from resolved: ResolvedActorStats) -> ActorValueInputs {
        let stats = resolved.stats.value
        let characterClass = characterClass(stats.characterClass)
        return ActorValueInputs(
            race: resolved.statsRace.value.flatMap { races[$0.rawValue] }?.stats ?? Race.Stats(),
            stats: stats,
            autoCalculatesStats: resolved.autoCalculatesStats.value,
            usesPlayerLevelMultiplier: resolved.usesPlayerLevelMultiplier.value,
            attributeWeights: characterClass?.attributeWeights ?? CharacterClass.AttributeWeights(),
            skillWeights: characterClass?.skillWeights ?? CharacterClass.SkillWeights()
        )
    }

    /// DNAM's three baked numbers, present only when the record carried all
    /// three. A partial DNAM is reported as absent rather than as a triple with
    /// invented zeros, because the whole point of this field is comparison.
    private func bakedValues(of stats: ActorBase.Stats) -> ActorValues? {
        guard
            let health = stats.bakedHealth,
            let magicka = stats.bakedMagicka,
            let stamina = stats.bakedStamina
        else {
            return nil
        }
        // Floored at zero the way `baseValues` floors its own result: the
        // editor stores the raw signed sum, and a negative baked magicka is the
        // same "no magicka" a derived one clamps to.
        return ActorValues(
            health: Float(max(0, health)),
            magicka: Float(max(0, magicka)),
            stamina: Float(max(0, stamina))
        )
    }
}
