// `MagicEffectControlProviding` conformance (issue #469, roadmap item 19.6):
// the live effect list, coverage counts and dev controls the Combat & Physics
// panel's Magic Effects section is written against.
//
// Every field below is a plain read off `ActiveEffectRuntime` and its tally,
// with no accounting invented at the UI — the same rule the actor-value panel
// conformance follows.

import Foundation

extension GameViewController: MagicEffectControlProviding {
    var magicEffectControlSnapshot: MagicEffectControlSnapshot {
        guard let runtime = magicEffects.runtime else { return .unavailable }
        let tally = runtime.tally
        let nearest = nearestActorValueHolder()
        return MagicEffectControlSnapshot(
            isAvailable: true,
            playerEffects: runtime.active(on: .player).map { readout(of: $0, runtime: runtime) },
            nearestActorName: nearest.map { name(ofActorValueHolder: $0) },
            nearestActorEffects: nearest.map { holder in
                runtime.active(on: holder).map { readout(of: $0, runtime: runtime) }
            } ?? [],
            runtimeActorCount: worldState.snapshot().entries.count { entry in
                entry.delta.component(ActiveEffectState.self) != nil
            },
            appliedCount: tally.applied,
            instantCount: tally.instantApplications,
            expiredCount: tally.expired,
            dispelledCount: tally.dispelled,
            skippedCount: tally.totalSkips,
            unimplementedLines: tally.unimplementedArchetypes.map { entry in
                "\(entry.archetype.description) x\(entry.count)"
            },
            lastActionText: magicEffects.lastActionText
        )
    }

    @discardableResult
    func consumeFirstCarriedMagicItem() -> String {
        guard magicEffects.runtime != nil else {
            magicEffects.lastActionText = "Magic effects unavailable: no game data loaded."
            return magicEffects.lastActionText
        }
        guard let item = firstCarriedMagicItem() else {
            magicEffects.lastActionText = "The player carries nothing to eat or drink."
            return magicEffects.lastActionText
        }
        return consumeMagicItem(item)
    }

    @discardableResult
    func dispelPlayerMagicEffects() -> String {
        guard magicEffects.runtime != nil else {
            magicEffects.lastActionText = "Magic effects unavailable: no game data loaded."
            return magicEffects.lastActionText
        }
        let removed = magicEffects.runtime?.dispelAll(on: .player) ?? 0
        magicEffects.lastActionText = removed == 0
            ? "No effect was acting on the player."
            : "Dispelled \(removed) effect(s) on the player."
        return magicEffects.lastActionText
    }

    // MARK: - Private

    private func readout(
        of effect: ActiveEffect,
        runtime: ActiveEffectRuntime
    ) -> ActiveEffectReadout {
        ActiveEffectReadout(
            name: magicEffectName(effect.effect, runtime: runtime),
            sourceName: effect.source.kind.describedName,
            mode: effect.mode,
            isDetrimental: effect.isDetrimental,
            magnitude: effect.values.first?.magnitude ?? 0,
            duration: effect.duration,
            remaining: effect.remaining,
            valueNames: effect.values.map { ActorValueIdentity.description(of: $0.index) }
        )
    }

    /// The MGEF's display name, falling back to its key so a line always names
    /// something even when the record moved out of the load order.
    private func magicEffectName(_ key: ReferenceKey, runtime: ActiveEffectRuntime) -> String {
        guard case let .plugin(name, objectID) = key else { return key.description }
        let resolved = ResolvedFormID(plugin: name, objectID: objectID)
        return runtime.effects.effect(resolved)?.displayName ?? key.description
    }
}
