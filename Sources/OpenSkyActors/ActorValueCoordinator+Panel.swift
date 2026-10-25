// The Combat readout's actor-value readouts and dev controls. Every field is a
// plain read off `ActorValueRuntime`.

import Foundation
import OpenSkyActorsInterface
import OpenSkyGameData
import OpenSkyWorldState

extension ActorValueCoordinator {
    public var snapshot: ActorValueControlSnapshot {
        guard runtime != nil else { return .unavailable }
        let nearest = world?.nearestActorValueHolder()
        return ActorValueControlSnapshot(
            nearestActor: nearest.map { readout(name: Self.name(of: $0)) },
            runtimeActorCount: store.snapshot().entries.count { entry in
                entry.delta.component(ActorValueState.self) != nil
            }
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

    private func readout(name: String) -> ActorValueReadout {
        ActorValueReadout(name: name)
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
