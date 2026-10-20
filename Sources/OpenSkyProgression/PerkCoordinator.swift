// The shell of the perk domain: owns the perk runtime, seeds an actor's
// authored `PRKR` list, and answers the entry-point questions the combat and
// magic formulas ask. The rules live in `PerkRuntime`.
// See docs/engine/coordinators.md.

import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyProgressionInterface

/// Owns the perk runtime and reads the world through `PerkWorld`. Without
/// game data the runtime stays nil, and every entry point returns the value
/// the formula already had.
@MainActor
public final class PerkCoordinator {
    /// Nil until `wire`.
    public private(set) var runtime: PerkRuntime?
    private var baselines: ActorPerkBaselineResolver?
    /// The plugin an actor's `PRKR` links are relative to.
    private var pluginName: String?
    /// An NPC is seeded the first time anything asks about it, not at cell
    /// build, so townsfolk who never fight write no perks into the save.
    private var seededActors: Set<ReferenceKey> = []

    let world: any PerkWorld

    public init(world: any PerkWorld) {
        self.world = world
    }

    public func wire(
        _ runtime: PerkRuntime,
        baselines: ActorPerkBaselineResolver?,
        pluginName: String?
    ) {
        self.baselines = baselines
        self.pluginName = pluginName
        store(runtime)
    }

    // MARK: - Ownership

    /// Applies the abilities the perk grants and sets the quest stages its quest
    /// effects name, such as Investor's merchant dialogue.
    ///
    /// - Returns: true when the perk was not already owned.
    @discardableResult
    public func add(_ perk: ReferenceKey, to holder: ActorValueHolder) -> Bool {
        guard var runtime else { return false }
        let changed = runtime.add(perk, to: holder)
        store(runtime)
        if changed {
            world.reconcileAbilities(on: holder, perks: runtime)
            setQuestStages(of: perk, in: runtime)
        }
        return changed
    }

    private func setQuestStages(of perk: ReferenceKey, in runtime: PerkRuntime) {
        guard let record = runtime.record(perk) else { return }
        for effect in record.effects {
            if case let .quest(quest?, stage) = effect.effect.data {
                world.setPerkQuestStage(stage, quest: quest, fromPlugin: record.sourcePlugin)
            }
        }
    }

    /// Revokes the abilities the perk granted.
    ///
    /// - Returns: true when the perk was owned.
    @discardableResult
    public func remove(_ perk: ReferenceKey, from holder: ActorValueHolder) -> Bool {
        guard var runtime else { return false }
        let changed = runtime.remove(perk, from: holder)
        store(runtime)
        if changed {
            world.reconcileAbilities(on: holder, perks: runtime)
        }
        return changed
    }

    /// The player is seeded with nothing: its perks are the ones it took.
    ///
    /// - Returns: how many perks the seed added, which is zero after the first call.
    @discardableResult
    public func seed(_ holder: ActorValueHolder) -> Int {
        guard
            var runtime,
            let baselines,
            let pluginName,
            !seededActors.contains(holder.key)
        else { return 0 }
        seededActors.insert(holder.key)
        let report = runtime.seed(
            baselines.baseline(for: holder.subject), fromPlugin: pluginName, to: holder
        )
        store(runtime)
        guard !report.added.isEmpty else { return 0 }
        world.reconcileAbilities(on: holder, perks: runtime)
        return report.added.count
    }

    // MARK: - Evaluating

    /// What `holder`'s perks make of `value` at `entryPoint`. Every wired seam goes
    /// through here, so the tally counts each evaluation once. `seams` holds the
    /// condition resolutions this one question adds, such as the lock being picked.
    public func modified(
        _ value: Float,
        at entryPoint: PerkEntryPoint,
        on holder: ActorValueHolder,
        subjects: PerkEvaluationSubjects,
        seams: ConditionContext = ConditionContext()
    ) -> Float {
        evaluate(on: holder, seams: seams) { runtime in
            runtime.modify(
                value,
                at: entryPoint,
                on: holder,
                subjects: subjects,
                actorValue: { [weak world] index in world?.actorValue(at: index, on: holder) }
            ).value
        } ?? value
    }

    /// `modified` with the owner and the placed references alone bound.
    public func modified(
        _ value: Float,
        at entryPoint: PerkEntryPoint,
        on holder: ActorValueHolder,
        target: ReferenceKey? = nil,
        attacker: ReferenceKey? = nil
    ) -> Float {
        modified(
            value,
            at: entryPoint,
            on: holder,
            subjects: PerkEvaluationSubjects(owner: holder.key, target: target, attacker: attacker)
        )
    }

    /// `modified` at a lockpicking entry point: `lock` is the locked reference, and
    /// `GetLockLevel` on it answers `level`, which the Novice to Master Locks perks read.
    public func modified(
        _ value: Float,
        at entryPoint: PerkEntryPoint,
        on holder: ActorValueHolder,
        lock: ReferenceKey,
        level: UInt8
    ) -> Float {
        var seams = ConditionContext()
        seams.locks = LockConditionResolution(levels: [lock: level])
        return modified(
            value,
            at: entryPoint,
            on: holder,
            subjects: PerkEvaluationSubjects(owner: holder.key, lockedReference: lock),
            seams: seams
        )
    }

    /// `Mod Skill Use` for one credited use of the player's skill: how much faster the
    /// skill improves. Rested, Lover's Comfort and the Guardian Stones work through it.
    public func skillUseMultiplier(_ usage: SkillUsageConditionResolution) -> Float {
        var seams = ConditionContext()
        seams.skillUsage = usage
        return modified(
            1,
            at: Self.skillUseEntryPoint,
            on: .player,
            subjects: PerkEvaluationSubjects(owner: ReferenceKey.player),
            seams: seams
        )
    }

    /// `Mod Skill Use`, by its xEdit position.
    public static let skillUseEntryPoint = PerkEntryPoint.modSkillUse

    /// The multiplier form, which every combat surface folds in beside its
    /// fortify term.
    public func multiplier(
        at entryPoint: PerkEntryPoint,
        on key: ReferenceKey,
        target: ReferenceKey? = nil,
        attacker: ReferenceKey? = nil
    ) -> Float {
        guard let holder = world.actorValueHolder(for: key) else { return 1 }
        return modified(1, at: entryPoint, on: holder, target: target, attacker: attacker)
    }

    /// `modified` for an actor named by key. `value` comes back unchanged when `key`
    /// has no actor values.
    public func modified(
        _ value: Float,
        at entryPoint: PerkEntryPoint,
        on key: ReferenceKey,
        subjects: (ReferenceKey) -> PerkEvaluationSubjects,
        seams: ConditionContext = ConditionContext()
    ) -> Float {
        guard let holder = world.actorValueHolder(for: key) else { return value }
        return modified(value, at: entryPoint, on: holder, subjects: subjects(key), seams: seams)
    }

    /// The effects at `entryPoint` that pick a spell, a text, or a button, highest
    /// priority first. Empty without a perk runtime.
    public func choices(
        at entryPoint: PerkEntryPoint,
        on key: ReferenceKey,
        subjects: (ReferenceKey) -> PerkEvaluationSubjects,
        seams: ConditionContext = ConditionContext()
    ) -> [PerkEntryPointChoice] {
        guard let holder = world.actorValueHolder(for: key) else { return [] }
        return evaluate(on: holder, seams: seams) { runtime in
            runtime.choices(at: entryPoint, on: holder, subjects: subjects(key))
        } ?? []
    }

    /// Runs `body` on the runtime with `seams` laid over its conditions for this one
    /// call, then stores what the evaluation counted.
    private func evaluate<Result>(
        on holder: ActorValueHolder,
        seams: ConditionContext,
        _ body: (inout PerkRuntime) -> Result
    ) -> Result? {
        guard runtime != nil else { return nil }
        seed(holder)
        refreshEffectPerks(on: holder)
        guard var runtime else { return nil }
        let base = runtime.conditions
        runtime.conditions = base.overlaid(by: seams)
        let result = body(&runtime)
        let random = runtime.conditions.random
        runtime.conditions = base
        runtime.conditions.random = random
        store(runtime)
        return result
    }

    /// Nil without a perk runtime, which is what `Actor.HasPerk` reports
    /// rather than answering false.
    public func ownership(of key: ReferenceKey) -> Set<ReferenceKey>? {
        guard runtime != nil, let holder = world.actorValueHolder(for: key) else { return nil }
        seed(holder)
        refreshEffectPerks(on: holder)
        return runtime.map { Set($0.state(of: holder).owned) }
    }

    /// Effects come and go every frame, so their perks are read when a question is asked.
    private func refreshEffectPerks(on holder: ActorValueHolder) {
        guard var runtime else { return }
        let granted = world.perksFromActiveEffects(on: holder)
        guard runtime.effectPerks[holder.key] ?? [] != granted else { return }
        runtime.effectPerks[holder.key] = granted.isEmpty ? nil : granted
        store(runtime)
    }

    private func store(_ runtime: PerkRuntime) {
        self.runtime = runtime
        world.perksChanged(runtime)
    }
}
