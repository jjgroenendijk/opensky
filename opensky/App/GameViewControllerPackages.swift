// Live app wiring for issue #201's engine-owned package selector. The future
// M16 panel reads the retained readouts; this file adds no UI.

import AppKit

struct PackageBridgeState {
    var runtime: ActorPackageRuntime?
    var registeredActors: [ReferenceKey: FormID] = [:]
}

extension GameViewController {
    func wirePackages(provider: any CellSceneProvider, renderer: Renderer) {
        guard let store = (provider as? PackageDataProviding)?.packageStore else { return }
        packages.runtime = ActorPackageRuntime(store: store)
        let advancePreviousSystems = renderer.onWorldUpdate
        renderer.onWorldUpdate = { [weak self, weak renderer] delta in
            advancePreviousSystems?(delta)
            self?.advancePackages(renderer: renderer)
        }
    }

    /// Reconciles streamed ACHRs before evaluating scheduled boundaries and
    /// mutable conditions. An actor leaving residency stops being simulated.
    func advancePackages(renderer: Renderer?) {
        guard var runtime = packages.runtime, let streamer, let renderer else { return }
        let residents = Dictionary(uniqueKeysWithValues: streamer.residentActorEntries()
            .compactMap { entry in entry.placedActor.map { (entry.key, $0.base) } })
        for actor in packages.registeredActors.keys where residents[actor] == nil {
            runtime.unregister(actor: actor)
            packages.registeredActors.removeValue(forKey: actor)
        }
        for actor in residents.keys.sorted()
            where packages.registeredActors[actor] != residents[actor]
        {
            guard
                let base = residents[actor],
                (try? runtime.register(actor: actor, base: base)) != nil
            else { continue }
            packages.registeredActors[actor] = base
        }

        var context: ConditionContext?
        runtime.advance(clock: renderer.gameClock) { _ in
            if let context {
                return context
            }
            let live = packageConditionContext(streamer: streamer, clock: renderer.gameClock)
            context = live
            return live
        }
        packages.runtime = runtime
    }

    /// Re-selects `actor`'s package immediately (issue #424).
    ///
    /// Combat suspends nothing — an actor that starts fighting simply stops
    /// acting on its package's movement, because the combat machine owns its
    /// mover from then on. What ending a pursuit needs is therefore not a
    /// resume of a saved procedure but a fresh selection: the world has moved on
    /// by however long the fight lasted, and the package the schedule names now
    /// is the one the actor should be doing. That is exactly
    /// `forceReevaluate(actor:clock:context:)`, which the package runtime
    /// already exposes for the gate panel.
    func resumePackage(for actor: ReferenceKey) {
        guard
            var runtime = packages.runtime,
            let streamer,
            let renderer,
            packages.registeredActors[actor] != nil
        else { return }
        runtime.forceReevaluate(
            actor: actor,
            clock: renderer.gameClock,
            context: packageConditionContext(streamer: streamer, clock: renderer.gameClock)
        )
        packages.runtime = runtime
    }

    /// Current state seam for issue #203's panel.
    func packageReadouts() -> [PackageActorReadout] {
        packages.runtime?.readouts() ?? []
    }

    private func packageConditionContext(
        streamer: CellStreamer,
        clock: GameClock
    ) -> ConditionContext {
        let snapshot = worldState.snapshot()
        return ConditionContext(
            globals: runtimeStateGlobalResolution(),
            quests: papyrusBridge?.questRuntime?.resolution() ?? .empty,
            aliases: papyrusBridge?.questRuntime?.aliasResolution() ?? .empty,
            actors: runtimeStateActorResolution(),
            detection: perceptionResolution(),
            referenceEnable: ReferenceEnableResolution(snapshot: snapshot),
            clock: clock,
            references: streamer.residentReferenceIndex()
        )
    }
}
