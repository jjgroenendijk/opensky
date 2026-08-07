// `ActorValueControlProviding` conformance (issue #194, roadmap item 15.3):
// the live readouts and dev controls a Combat panel is written against.
//
// The protocol and this conformance ship now; the panel itself ships with the
// M15 acceptance gate (item 15.9), which is what the issue asks for. Writing
// the conformance now is what proves the runtime can answer the questions a
// panel asks — every field below is a plain read off `ActorValueRuntime`, with
// no accounting invented at the UI.

import Foundation

extension GameViewController: ActorValueControlProviding {
    var actorValueTarget: ActorValueTargetSelector {
        get { actorValues.target }
        set { actorValues.target = newValue }
    }

    var actorValueControlSnapshot: ActorValueControlSnapshot {
        guard let runtime = actorValues.runtime else { return .unavailable }
        let nearest = nearestActorValueHolder()
        return ActorValueControlSnapshot(
            isAvailable: true,
            player: readout(of: .player, name: "Player", runtime: runtime),
            nearestActor: nearest.map {
                readout(of: $0, name: name(ofActorValueHolder: $0), runtime: runtime)
            },
            target: actorValues.target,
            runtimeActorCount: worldState.snapshot().entries.count { entry in
                entry.delta.component(ActorValueState.self) != nil
            },
            lastActionText: actorValues.lastActionText
        )
    }

    @discardableResult
    func damageSelectedActor(_ kind: ActorValueKind, by amount: Float) -> String {
        apply(verb: "Damaged") { runtime, holder in
            runtime.damage(kind, by: amount, on: holder)
        }
    }

    @discardableResult
    func restoreSelectedActor(_ kind: ActorValueKind, by amount: Float) -> String {
        apply(verb: "Restored") { runtime, holder in
            runtime.restore(kind, by: amount, on: holder)
        }
    }

    @discardableResult
    func restoreSelectedActorFully() -> String {
        apply(verb: "Refilled") { runtime, holder in
            runtime.restoreAll(on: holder)
        }
    }

    @discardableResult
    func resetSelectedActorValues() -> String {
        guard let runtime = actorValues.runtime else { return Self.noActorValueText }
        guard let holder = selectedActorValueHolder() else {
            return noActorValueTargetText()
        }
        let removed = runtime.reset(holder)
        actorValues.lastActionText = removed
            ? "Reset \(name(ofActorValueHolder: holder)) to derived values."
            : "\(name(ofActorValueHolder: holder)) already reads from records."
        return actorValues.lastActionText
    }

    // MARK: - Private

    private static let noActorValueText =
        "Actor values unavailable: no game data loaded."

    /// The holder the dev controls act on.
    private func selectedActorValueHolder() -> ActorValueHolder? {
        switch actorValues.target {
        case .player: .player
        case .nearestActor: nearestActorValueHolder()
        }
    }

    private func noActorValueTargetText() -> String {
        switch actorValues.target {
        case .player: "No player actor values."
        case .nearestActor: "No resident actor to act on."
        }
    }

    /// A holder's display name: its NPC_ base FormID, which is what the user
    /// types into the record dump to see what it resolved to.
    private func name(ofActorValueHolder holder: ActorValueHolder) -> String {
        switch holder.subject {
        case .player: "Player"
        case let .actor(base): "\(holder.key.description) (base \(base))"
        case .generated: holder.key.description
        }
    }

    private func readout(
        of holder: ActorValueHolder,
        name: String,
        runtime: ActorValueRuntime
    ) -> ActorValueReadout {
        let baseline = runtime.baseline(of: holder)
        let derived = derivedActorValues(of: holder)
        return ActorValueReadout(
            name: name,
            current: runtime.current(of: holder),
            maximums: baseline.maximums,
            regenPercentPerSecond: baseline.regenPercentPerSecond,
            level: derived?.level ?? 1,
            autoCalculatesStats: derived?.autoCalculatesStats ?? false,
            hasZeroHealth: runtime.hasZeroHealth(holder)
        )
    }

    /// The full derivation for an actor, for the two explanatory fields the
    /// baseline does not carry. Nil for the player and for a broken chain,
    /// which is why both fields have a documented default above.
    private func derivedActorValues(of holder: ActorValueHolder) -> ResolvedActorValues? {
        guard
            case let .actor(base) = holder.subject,
            let resolver = actorValues.runtime?.baselines.resolver
        else { return nil }
        return try? resolver.resolve(base: base)
    }

    private func apply(
        verb: String,
        _ change: (ActorValueRuntime, ActorValueHolder) -> ActorValueState
    ) -> String {
        guard let runtime = actorValues.runtime else { return Self.noActorValueText }
        guard let holder = selectedActorValueHolder() else {
            return noActorValueTargetText()
        }
        let state = change(runtime, holder)
        actorValues.lastActionText = String(
            format: "%@ %@: %.1f / %.1f / %.1f.",
            verb,
            name(ofActorValueHolder: holder),
            state.current.health,
            state.current.magicka,
            state.current.stamina
        )
        return actorValues.lastActionText
    }
}
