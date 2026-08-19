// Session wiring for perks (issue #497, roadmap item 20.4): builds the perk
// runtime over the provider's PERK index, seeds an actor from its authored
// `PRKR` list, keeps the abilities its perks grant applied, and answers the
// entry-point questions the combat and magic formulas ask.
//
// AppKit stays in this controller satellite; the runtime, the evaluator, the
// component and the ability reconcile are all engine types that build into
// `openskycli` and are testable without a window.
//
// ## Seeding is lazy, exactly as the spell grant is
//
// An NPC's `PRKR` list is granted the first time anything asks about that actor
// — a swing at it, a perk query, a cast — rather than for every resident actor
// at cell build, because a cell of forty townsfolk who never fight would
// otherwise write forty perk components into the save to say what their base
// records already say. The seed is idempotent, so an actor asked about twice is
// seeded once. The player is seeded with nothing: there is no NPC_ record behind
// the player in this engine, and the perks a player has are the ones they took.

import AppKit

/// Perk state the controller owns. Extensions cannot add stored properties, so
/// it lives as one value on `GameViewController`.
struct PerkBridgeState {
    /// Ownership plus entry-point evaluation, built by `wirePerks` when the
    /// provider can supply a PERK index. nil without game data, and then every
    /// entry point evaluates to the value the formula already had.
    var runtime: PerkRuntime?
    /// Record-side resolution of an actor's authored `PRKR` list, built beside
    /// the runtime from the same provider indexes the actor-value baselines
    /// come from. nil without game data.
    var baselines: ActorPerkBaselineResolver?
    /// The plugin an actor's `PRKR` links are relative to, which is the base
    /// plugin the record indexes were built from.
    var pluginName: String?
    /// Actors whose authored perk list has already been seeded, so the seed
    /// happens once per actor per session rather than once per swing.
    var seededActors: Set<ReferenceKey> = []
    /// Human-readable result of the last perk action.
    var lastActionText = "No perk action yet."
}

extension GameViewController {
    /// Builds the perk runtime over the provider's PERK index.
    ///
    /// Wired after `wireCasting`, because the cast loop folds the spell-cost
    /// entry point through this runtime and takes it by value: the caster has
    /// to exist before it can be handed one.
    func wirePerks(provider: any CellSceneProvider) {
        guard let store = (provider as? ProgressionDataProviding)?.perkStore else { return }
        var runtime = PerkRuntime(store: worldState, perks: store)
        runtime.conditions = ConditionContext(globals: runtimeStateGlobalResolution())
        perks.runtime = runtime
        perks.pluginName = (provider as? MagicDataProviding)?.magicItemPluginName
        if
            let resolver = (provider as? ActorValueDataProviding)?
                .actorValueBaselines?.resolver
        {
            perks.baselines = ActorPerkBaselineResolver(actorValues: resolver)
        }
        // The cast loop's copy. A struct over the same store, so the two share
        // every write and differ only in the tally each one grows.
        casting.runtime?.perks = runtime
    }

    // MARK: - Ownership

    /// Gives `holder` one perk and applies whatever abilities it grants.
    ///
    /// - Returns: true when the perk was not already owned.
    @discardableResult
    func addPerk(_ perk: ReferenceKey, to holder: ActorValueHolder) -> Bool {
        guard var runtime = perks.runtime else { return false }
        let changed = runtime.add(perk, to: holder)
        perks.runtime = runtime
        casting.runtime?.perks = runtime
        if changed {
            reconcilePerkAbilities(on: holder)
        }
        return changed
    }

    /// Takes one perk away and revokes whatever abilities it granted.
    ///
    /// - Returns: true when the perk was owned.
    @discardableResult
    func removePerk(_ perk: ReferenceKey, from holder: ActorValueHolder) -> Bool {
        guard var runtime = perks.runtime else { return false }
        let changed = runtime.remove(perk, from: holder)
        perks.runtime = runtime
        casting.runtime?.perks = runtime
        if changed {
            reconcilePerkAbilities(on: holder)
        }
        return changed
    }

    /// Seeds `holder` from its authored `PRKR` list once, and applies the
    /// abilities the seeded perks grant.
    ///
    /// - Returns: how many perks the seed added, which is zero on every call
    ///   after the first.
    @discardableResult
    func seedActorPerks(to holder: ActorValueHolder) -> Int {
        guard
            var runtime = perks.runtime,
            let baselines = perks.baselines,
            let plugin = perks.pluginName,
            !perks.seededActors.contains(holder.key)
        else { return 0 }
        perks.seededActors.insert(holder.key)
        let report = runtime.seed(
            baselines.baseline(for: holder.subject), fromPlugin: plugin, to: holder
        )
        perks.runtime = runtime
        casting.runtime?.perks = runtime
        guard !report.added.isEmpty else { return 0 }
        reconcilePerkAbilities(on: holder)
        return report.added.count
    }

    /// Makes the constant abilities on `holder` match the perks it owns.
    @discardableResult
    func reconcilePerkAbilities(on holder: ActorValueHolder) -> PerkAbilityReport {
        guard
            let runtime = perks.runtime,
            var effects = magicEffects.runtime,
            let spells = casting.runtime?.spellbook.spells
        else { return .none }
        let report = PerkAbilityApplication.reconcile(
            on: holder, perks: runtime, spells: spells, using: &effects
        )
        magicEffects.runtime = effects
        return report
    }

    // MARK: - Evaluating

    /// What `holder`'s perks make of `value` at `entryPoint`.
    ///
    /// The one door every wired seam goes through, so a formula never reaches
    /// into the runtime itself and the tally counts every evaluation once.
    /// Without a perk runtime the value comes back untouched, which is the
    /// identity rule the whole subsystem follows.
    func perkModified(
        _ value: Float,
        at entryPoint: PerkEntryPoint,
        on holder: ActorValueHolder,
        target: ReferenceKey? = nil,
        attacker: ReferenceKey? = nil
    ) -> Float {
        guard var runtime = perks.runtime else { return value }
        seedActorPerks(to: holder)
        runtime = perks.runtime ?? runtime
        let outcome = runtime.modify(
            value,
            at: entryPoint,
            on: holder,
            subjects: PerkEvaluationSubjects(
                owner: holder.key, target: target, attacker: attacker
            ),
            actorValue: { [weak self] index in
                self?.actorValues.runtime?.value(at: index, on: holder)
            }
        )
        perks.runtime = runtime
        casting.runtime?.perks = runtime
        return outcome.value
    }

    /// The multiplier form of the same question, which is what every combat
    /// surface folds in beside its fortify term.
    func perkMultiplier(
        at entryPoint: PerkEntryPoint,
        on key: ReferenceKey,
        target: ReferenceKey? = nil,
        attacker: ReferenceKey? = nil
    ) -> Float {
        guard let holder = actorValueHolder(for: key) else { return 1 }
        return perkModified(
            1, at: entryPoint, on: holder, target: target, attacker: attacker
        )
    }

    /// The perks `key` owns, or nil when this session runs no perk runtime —
    /// which is what `Actor.HasPerk` reports rather than answering false.
    func perkOwnership(of key: ReferenceKey) -> Set<ReferenceKey>? {
        guard let runtime = perks.runtime, let holder = actorValueHolder(for: key) else {
            return nil
        }
        seedActorPerks(to: holder)
        return Set((perks.runtime ?? runtime).state(of: holder).owned)
    }
}

extension GameViewController {
    /// `Mod Attack Damage` (35), the entry point every vanilla weapon damage
    /// perk hooks and the most-hooked one in the game (81 effects,
    /// docs/formats/perks.md).
    static let attackDamageEntryPoint = PerkEntryPoint(rawValue: 35)
    /// `Mod Percent Blocked` (39), which is where Shield Wall and its ranks
    /// live.
    static let percentBlockedEntryPoint = PerkEntryPoint(rawValue: 39)
}
