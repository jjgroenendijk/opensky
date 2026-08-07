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
    let classes: CharacterClassIndex
    let settings: ActorValueLevelSettings
    /// Level a `PC Level Mult` actor scales against. There is no player level
    /// before M18, so this defaults to 1 and every scaled actor resolves at the
    /// bottom of its range.
    let playerLevel: Int

    init(
        templates: ActorTemplateResolver,
        races: [UInt32: Race],
        classes: CharacterClassIndex = CharacterClassIndex(),
        settings: ActorValueLevelSettings = .documentedDefaults,
        playerLevel: Int = 1
    ) {
        self.templates = templates
        self.races = races
        self.classes = classes
        self.settings = settings
        self.playerLevel = playerLevel
    }

    /// Builds every index this resolver needs from one plugin file.
    ///
    /// `settings` is passed in rather than loaded here: the GMST store spans
    /// the whole load order and a caller that already built one must not pay
    /// for a second walk.
    static func build(
        from file: ESMFile,
        localized: Bool,
        settings: ActorValueLevelSettings = .documentedDefaults,
        playerLevel: Int = 1
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
            classes: CharacterClassIndex.build(from: file, localized: localized),
            settings: settings,
            playerLevel: playerLevel
        )
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
        return ResolvedActorValues(
            base: base,
            maximums: ActorValueDerivation.baseValues(
                inputs: gathered,
                settings: settings,
                playerLevel: playerLevel
            ),
            regenPercentPerSecond: ActorValues(
                health: gathered.race.healthRegenPercent,
                magicka: gathered.race.magickaRegenPercent,
                stamina: gathered.race.staminaRegenPercent
            ),
            level: ActorValueDerivation.level(inputs: gathered, playerLevel: playerLevel),
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
        return ActorValueInputs(
            race: resolved.statsRace.value.flatMap { races[$0.rawValue] }?.stats ?? Race.Stats(),
            stats: stats,
            autoCalculatesStats: resolved.autoCalculatesStats.value,
            usesPlayerLevelMultiplier: resolved.usesPlayerLevelMultiplier.value,
            attributeWeights: classes[stats.characterClass]?.attributeWeights
                ?? CharacterClass.AttributeWeights()
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
