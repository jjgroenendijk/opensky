// The shell of the perk domain: owns the perk runtime, seeds an actor's
// authored `PRKR` list, and answers the entry-point questions the combat and
// magic formulas ask. The rules live in `PerkRuntime`.
// See docs/engine/coordinators.md.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyProgressionInterface
import OpenSkyWorldState

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

    weak var world: (any PerkWorld)?

    public init() {}

    public func attach(world: any PerkWorld) {
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

    /// Applies the abilities the perk grants.
    ///
    /// - Returns: true when the perk was not already owned.
    @discardableResult
    public func add(_ perk: ReferenceKey, to holder: ActorValueHolder) -> Bool {
        guard var runtime else { return false }
        let changed = runtime.add(perk, to: holder)
        store(runtime)
        if changed {
            world?.reconcileAbilities(on: holder, perks: runtime)
        }
        return changed
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
            world?.reconcileAbilities(on: holder, perks: runtime)
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
        world?.reconcileAbilities(on: holder, perks: runtime)
        return report.added.count
    }

    // MARK: - Evaluating

    /// What `holder`'s perks make of `value` at `entryPoint`. Every wired seam
    /// goes through here, so the tally counts each evaluation once.
    public func modified(
        _ value: Float,
        at entryPoint: PerkEntryPoint,
        on holder: ActorValueHolder,
        target: ReferenceKey? = nil,
        attacker: ReferenceKey? = nil
    ) -> Float {
        guard runtime != nil else { return value }
        seed(holder)
        guard var runtime else { return value }
        let outcome = runtime.modify(
            value,
            at: entryPoint,
            on: holder,
            subjects: PerkEvaluationSubjects(owner: holder.key, target: target, attacker: attacker),
            actorValue: { [weak world] index in world?.actorValue(at: index, on: holder) }
        )
        store(runtime)
        return outcome.value
    }

    /// The multiplier form, which every combat surface folds in beside its
    /// fortify term.
    public func multiplier(
        at entryPoint: PerkEntryPoint,
        on key: ReferenceKey,
        target: ReferenceKey? = nil,
        attacker: ReferenceKey? = nil
    ) -> Float {
        guard let holder = world?.actorValueHolder(for: key) else { return 1 }
        return modified(1, at: entryPoint, on: holder, target: target, attacker: attacker)
    }

    /// Nil without a perk runtime, which is what `Actor.HasPerk` reports
    /// rather than answering false.
    public func ownership(of key: ReferenceKey) -> Set<ReferenceKey>? {
        guard runtime != nil, let holder = world?.actorValueHolder(for: key) else { return nil }
        seed(holder)
        return runtime.map { Set($0.state(of: holder).owned) }
    }

    private func store(_ runtime: PerkRuntime) {
        self.runtime = runtime
        world?.perksChanged(runtime)
    }
}
