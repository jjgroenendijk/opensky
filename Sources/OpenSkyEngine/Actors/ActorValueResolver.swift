// Plugin-side seam of the actor-value subsystem (issue #194, roadmap item
// 15.3): turns an NPC_ FormID into the derived base health, magicka and
// stamina, by walking the template chain for the stat fields and looking up the
// RACE and CLAS records they name.
//
// Separate from `ActorValueRuntime` on purpose, and mirroring how
// `InventoryBaselineResolver` sits beside `InventoryRuntime`: this side is
// immutable, reads only records, and is safe to build once per session; the
// runtime side is mutable, main-actor, and knows nothing about records. The
// runtime asks this type for a baseline and never re-derives one itself.
//
// Documented in docs/engine/actor-values.md.

import Foundation

/// Why an actor's values could not be derived.
///
/// Deliberately few. A missing race or class is *not* an error — it degrades to
/// zero starting attributes and zero class weights, which is what a record that
/// names neither should produce. Only a chain that cannot be walked at all
/// fails, and that failure already has a type.
nonisolated enum ActorValueResolveError: Error, Equatable {
    /// The template chain could not be walked; carries the underlying failure.
    case unresolvedChain(ActorResolveError)
}

/// One actor's derived baseline plus the records it came from, so an inspector
/// can say *why* a number is what it is rather than only what it is.
nonisolated struct ResolvedActorValues: Equatable {
    let base: FormID
    /// Base maximums: what `ActorValueState` starts full at.
    let maximums: ActorValues
    /// Percent of each maximum restored per second, from the race.
    let regenPercentPerSecond: ActorValues
    /// Base values for the non-primary actor values this actor's records
    /// author, keyed by vanilla table index (issue #468). An index absent here
    /// reads `ActorValueIdentity.defaultValue(at:)`.
    let generalBaseValues: [Int32: Float]
    /// The level the derivation used.
    let level: Int
    /// RACE the starting attributes came from, nil when the chain names none.
    ///
    /// This is the *stats*-resolved race, not the traits-resolved one the
    /// renderer skins the actor with; see `ResolvedActorStats.statsRace`.
    let race: FormID?
    /// CLAS the attribute weights came from, nil when the chain names none.
    let characterClass: FormID?
    /// NPC_ that supplied the stat words, which is where an unexpected offset
    /// is actually authored.
    let statsSource: FormID
    /// Whether the per-level spread applied at all.
    let autoCalculatesStats: Bool
    /// Whether the level was scaled against the player's.
    let usesPlayerLevelMultiplier: Bool
    /// DNAM's baked attributes, when the record carried them. Never an input —
    /// see `ActorBase.Stats.bakedHealth`.
    let bakedValues: ActorValues?
}

/// Derives actor values from pre-built single-plugin record indexes, the same
/// raw-`UInt32` keying `ActorTemplateResolver` and `ActorVisualResolver` use.
nonisolated struct ActorValueResolver {
    let templates: ActorTemplateResolver
    let races: [UInt32: Race]
    /// Load-order-wide CLAS lookup (issue #496). Cross-plugin since item 20.3,
    /// which is why the plugin the NPC_ records came from travels beside it:
    /// a class link resolves relative to the plugin carrying it.
    let classes: CharacterClassStore
    /// Plugin the NPC_ and RACE indexes were built from, which is what a CLAS
    /// link in one of those records resolves against.
    let pluginName: String
    let settings: ActorValueLevelSettings
    /// Where the level a `PC Level Mult` actor scales against is published
    /// (issue #499). Shared by reference, so a level-up moves every derivation
    /// on its next read rather than needing this value rebuilt; a session with
    /// no progression leaves it at 1 and every scaled actor resolves at the
    /// bottom of its range, which is what it did before item 20.6.
    let playerLevelSource: PlayerLevelSource

    /// The level as of right now.
    var playerLevel: Int {
        playerLevelSource.level
    }

    init(
        templates: ActorTemplateResolver,
        races: [UInt32: Race],
        classes: CharacterClassStore = CharacterClassStore(),
        pluginName: String = "",
        settings: ActorValueLevelSettings = .documentedDefaults,
        playerLevel: PlayerLevelSource = PlayerLevelSource()
    ) {
        self.templates = templates
        self.races = races
        self.classes = classes
        self.pluginName = pluginName
        self.settings = settings
        playerLevelSource = playerLevel
    }

    /// Builds every index this resolver needs from one plugin file.
    ///
    /// `settings` is passed in rather than loaded here: the GMST store spans
    /// the whole load order and a caller that already built one must not pay
    /// for a second walk. `classes` is passed in for the same reason and for
    /// one more — a caller with the whole load order hands over a store built
    /// across it, so a patch plugin's CLAS override is seen; a caller with one
    /// file gets a store over that file alone.
    static func build(
        from file: ESMFile,
        localized: Bool,
        pluginName: String,
        classes: CharacterClassStore? = nil,
        settings: ActorValueLevelSettings = .documentedDefaults,
        playerLevel: PlayerLevelSource = PlayerLevelSource()
    ) -> ActorValueResolver {
        var races: [UInt32: Race] = [:]
        if let top = file.topGroup(of: "RACE"), let children = try? top.children() {
            for case let .record(record) in children {
                guard record.type == "RACE", !record.isDeleted else { continue }
                races[record.formID] = try? Race(record: record, localized: localized)
            }
        }
        return ActorValueResolver(
            templates: ActorTemplateResolver.build(from: file, localized: localized),
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
    func characterClass(_ id: FormID?) -> CharacterClass? {
        classes.resolve(id, fromPlugin: pluginName)?.characterClass
    }

    /// The derivation inputs for one NPC_, gathered through its template chain.
    ///
    /// - Throws: `ActorValueResolveError.unresolvedChain` when the TPLT walk
    ///   fails — a cycle, a dangling target, an empty leveled list.
    func inputs(base: FormID) throws -> ActorValueInputs {
        let resolved = try resolveStats(base: base)
        return inputs(from: resolved)
    }

    /// The full derived baseline for one NPC_.
    func resolve(base: FormID) throws -> ResolvedActorValues {
        let resolved = try resolveStats(base: base)
        let gathered = inputs(from: resolved)
        let stats = resolved.stats.value
        // Read once: the three derivations below must agree about the level,
        // and a level-up landing between two of them would produce a baseline
        // whose maximums and reported level disagree.
        let currentPlayerLevel = playerLevel
        return ResolvedActorValues(
            base: base,
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
