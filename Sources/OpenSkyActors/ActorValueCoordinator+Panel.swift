// The Combat panel's actor-value readouts and dev controls. Every field is a
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
            lastActionText: lastActionText
        )
    }

    @discardableResult
    public func damageSelected(by amount: Float) -> String {
        applyToSelection(verb: "Damaged") { runtime, holder, index in
            runtime.damage(at: index, by: amount, on: holder)
        }
    }

    @discardableResult
    public func restoreSelected(by amount: Float) -> String {
        applyToSelection(verb: "Restored") { runtime, holder, index in
            runtime.restore(at: index, by: amount, on: holder)
        }
    }

    @discardableResult
    public func setSelectedValue(to value: Float) -> String {
        applyToSelection(verb: "Set") { runtime, holder, index in
            runtime.setValue(at: index, to: value, on: holder)
        }
    }

    @discardableResult
    public func setSelectedBase(to value: Float) -> String {
        applyToSelection(verb: "Set the base of") { runtime, holder, index in
            runtime.setBase(at: index, to: value, on: holder)
        }
    }

    @discardableResult
    public func restoreSelectedFully() -> String {
        guard let runtime else { return Self.noActorValueText }
        guard let holder = selectedHolder() else { return noTargetText() }
        let state = runtime.restoreAll(on: holder)
        lastActionText = String(
            format: "Refilled %@: %.1f / %.1f / %.1f.",
            Self.name(of: holder),
            state.current.health,
            state.current.magicka,
            state.current.stamina
        )
        return lastActionText
    }

    @discardableResult
    public func resetSelected() -> String {
        guard let runtime else { return Self.noActorValueText }
        guard let holder = selectedHolder() else { return noTargetText() }
        lastActionText = runtime.reset(holder)
            ? "Reset \(Self.name(of: holder)) to derived values."
            : "\(Self.name(of: holder)) already reads from records."
        return lastActionText
    }

    // MARK: - Private

    private static let noActorValueText = "Actor values unavailable: no game data loaded."

    private func selectedHolder() -> ActorValueHolder? {
        switch target {
        case .player: .player
        case .nearestActor: world?.nearestActorValueHolder()
        }
    }

    private func noTargetText() -> String {
        switch target {
        case .player: "No player actor values."
        case .nearestActor: "No resident actor to act on."
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
        return try? resolver.resolve(base: base)
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
    ) -> String {
        guard let runtime else { return Self.noActorValueText }
        guard let holder = selectedHolder() else { return noTargetText() }
        let index = selection
        guard change(runtime, holder, index) else {
            lastActionText = "\(ActorValueIdentity.description(of: index)) is not an actor value."
            return lastActionText
        }
        lastActionText = String(
            format: "%@ %@ %@: now %.1f.",
            verb,
            Self.name(of: holder),
            ActorValueIdentity.description(of: index),
            runtime.value(at: index, on: holder) ?? 0
        )
        return lastActionText
    }
}
