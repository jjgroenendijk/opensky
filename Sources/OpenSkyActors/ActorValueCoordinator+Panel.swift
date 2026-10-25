// The Combat readout's actor-value readouts and dev controls. Every field is a
// plain read off `ActorValueRuntime`.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

extension ActorValueCoordinator {
    public var snapshot: ActorValueControlSnapshot {
        guard let runtime else { return .unavailable }
        let nearest = world?.nearestActorValueHolder()
        return ActorValueControlSnapshot(
            isAvailable: true,
            player: readout(of: .player, name: "Player", runtime: runtime),
            nearestActor: nearest.map {
                readout(of: $0, name: Self.name(of: $0), runtime: runtime)
            },
            target: target,
            selection: inspection(runtime: runtime),
            runtimeActorCount: store.snapshot().entries.count { entry in
                entry.delta.component(ActorValueState.self) != nil
            },
            lastActionText: lastAction.text
        )
    }

    @discardableResult
    public func damageSelected(by amount: Float) -> ActorValueActionOutcome {
        applyToSelection(verb: "Damaged") { runtime, holder, index in
            runtime.damage(at: index, by: amount, on: holder)
        }
    }

    @discardableResult
    public func setSelectedValue(to value: Float) -> ActorValueActionOutcome {
        applyToSelection(verb: "Set") { runtime, holder, index in
            runtime.setValue(at: index, to: value, on: holder)
        }
    }

    @discardableResult
    public func restoreSelectedFully() -> ActorValueActionOutcome {
        guard let runtime else { return .unavailable }
        guard let holder = selectedHolder() else { return .noTarget(target) }
        let state = runtime.restoreAll(on: holder)
        return record(.refilled(
            actor: Self.name(of: holder),
            health: state.current.health,
            magicka: state.current.magicka,
            stamina: state.current.stamina
        ))
    }

    @discardableResult
    public func resetSelected() -> ActorValueActionOutcome {
        guard let runtime else { return .unavailable }
        guard let holder = selectedHolder() else { return .noTarget(target) }
        return record(.reset(actor: Self.name(of: holder), changed: runtime.reset(holder)))
    }

    // MARK: - Private

    private func record(_ outcome: ActorValueActionOutcome) -> ActorValueActionOutcome {
        lastAction = outcome
        return outcome
    }

    private func selectedHolder() -> ActorValueHolder? {
        switch target {
        case .player: .player
        case .nearestActor: world?.nearestActorValueHolder()
        }
    }

    private func readout(
        of holder: ActorValueHolder,
        name: String,
        runtime: ActorValueRuntime
    ) -> ActorValueReadout {
        let derived = derivedValues(of: holder, runtime: runtime)
        return ActorValueReadout(
            name: name,
            current: runtime.current(of: holder),
            // Effective maximums, so a base write and a fortify both show on the bar.
            maximums: runtime.maximums(of: holder),
            regenPercentPerSecond: runtime.baseline(of: holder).regenPercentPerSecond,
            level: derived?.level ?? 1,
            autoCalculatesStats: derived?.autoCalculatesStats ?? false,
            hasZeroHealth: runtime.hasZeroHealth(holder)
        )
    }

    /// Nil for the player and for a broken template chain.
    private func derivedValues(
        of holder: ActorValueHolder,
        runtime: ActorValueRuntime
    ) -> ResolvedActorValues? {
        guard case let .actor(base) = holder.subject, let resolver = runtime.baselines.resolver
        else { return nil }
        return try? resolver.rolling(runtime.leveledRoll(of: holder, base: base))
            .resolve(base: base)
    }

    /// Falls back to the player when no resident actor answers, so the line is
    /// never blank.
    private func inspection(runtime: ActorValueRuntime) -> ActorValueInspection {
        let holder = selectedHolder() ?? .player
        let index = selection
        let name = ActorValueIdentity.description(of: index)
        guard let current = runtime.value(at: index, on: holder) else {
            return ActorValueInspection(
                name: name, index: index, current: 0, base: 0, permanent: 0, temporary: 0,
                damage: 0, resistanceFraction: nil
            )
        }
        let entry = runtime.entry(at: index, on: holder)
        return ActorValueInspection(
            name: name,
            index: index,
            current: current,
            base: runtime.baseValue(at: index, on: holder) ?? 0,
            permanent: entry?.permanent ?? 0,
            temporary: entry?.temporary ?? 0,
            damage: entry?.damage ?? 0,
            resistanceFraction: runtime.resistanceFraction(at: index, on: holder)
        )
    }

    /// Reports the selected value afterwards, not the three bars: the point of
    /// the control is the value the user selected.
    private func applyToSelection(
        verb: String,
        _ change: (ActorValueRuntime, ActorValueHolder, Int32) -> Bool
    ) -> ActorValueActionOutcome {
        guard let runtime else { return .unavailable }
        guard let holder = selectedHolder() else { return .noTarget(target) }
        let index = selection
        guard change(runtime, holder, index) else { return record(.notAnActorValue(index)) }
        return record(.changed(
            verb: verb,
            actor: Self.name(of: holder),
            index: index,
            value: runtime.value(at: index, on: holder) ?? 0
        ))
    }
}
