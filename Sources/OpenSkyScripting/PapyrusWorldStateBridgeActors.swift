// `PapyrusWorldActorBridge` conformance. Values go through `ActorValueRuntime`,
// deaths through `RagdollRuntime.noteZeroHealth(of:killer:)`, and fights through
// `CombatLoopRuntime`, like the player's. Collaborators are closures, so wiring
// order does not matter. See docs/engine/papyrus-actor-natives.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldInterface
import OpenSkyWorldState

extension PapyrusWorldStateBridge {
    // MARK: - Reading

    public func actorState(for key: ReferenceKey) -> PapyrusActorState? {
        guard let values = actorValueRuntime?(), let holder = actorHolder(for: key) else {
            return nil
        }
        let baseline = values.baseline(of: holder)
        return PapyrusActorState(
            current: values.current(of: holder),
            maximums: values.maximums(of: holder),
            isDead: worldState.component(ActorDeathState.self, for: key)?.isDead ?? false,
            isInCombat: isActorInCombat(key),
            weaponDrawState: weaponDrawState?(key),
            general: values.resolvedEntries(of: holder),
            generalBaseline: baseline.basesByIndex,
            level: baseline.level
        )
    }

    // MARK: - Writing

    @discardableResult
    public func damageActorValue(
        at index: Int32, by amount: Float, on key: ReferenceKey
    ) -> PapyrusActorState? {
        guard let values = actorValueRuntime?(), let holder = actorHolder(for: key) else {
            return nil
        }
        guard values.damage(at: index, by: amount, on: holder) else { return nil }
        // The zero-health check is here rather than in the native because this
        // is the layer that can act on it: a blow that empties the bar has to
        // become a death on the same call, or a script that damages and then
        // asks `IsDead()` reads a live actor lying on the floor.
        if
            ActorValueIdentity.kind(at: index) == .health,
            values.hasZeroHealth(holder)
        {
            ragdollRuntime?()?.noteZeroHealth(of: key)
        }
        return actorState(for: key)
    }

    @discardableResult
    public func restoreActorValue(
        at index: Int32, by amount: Float, on key: ReferenceKey
    ) -> PapyrusActorState? {
        guard let values = actorValueRuntime?(), let holder = actorHolder(for: key) else {
            return nil
        }
        guard values.restore(at: index, by: amount, on: holder) else { return nil }
        return actorState(for: key)
    }

    @discardableResult
    public func writeActorValue(
        _ write: PapyrusActorValueWrite,
        at index: Int32,
        to value: Float,
        on key: ReferenceKey
    ) -> PapyrusActorState? {
        guard let values = actorValueRuntime?(), let holder = actorHolder(for: key) else {
            return nil
        }
        let written = switch write {
        case .setBase: values.setBase(at: index, to: value, on: holder)
        case .modify: values.addModifier(value, to: .permanent, at: index, on: holder)
        case .force: values.forceValue(at: index, to: value, on: holder)
        }
        guard written else { return nil }
        // The same zero-health route `damageActorValue` takes, and for the same
        // reason: a script that forces health to zero has killed the actor, and
        // the death has to land on this call rather than on the next frame.
        if
            ActorValueIdentity.kind(at: index) == .health,
            values.hasZeroHealth(holder)
        {
            ragdollRuntime?()?.noteZeroHealth(of: key)
        }
        return actorState(for: key)
    }

    @discardableResult
    public func startActorCombat(_ key: ReferenceKey, target: ReferenceKey) -> Bool {
        combatRuntime?()?.startCombat(key, with: target) ?? false
    }

    @discardableResult
    public func stopActorCombat(_ key: ReferenceKey) -> Bool {
        combatRuntime?()?.stopCombat(key) ?? false
    }

    @discardableResult
    public func killActor(_ key: ReferenceKey, killer: ReferenceKey?) -> Bool {
        guard let values = actorValueRuntime?(), let holder = actorHolder(for: key) else {
            return false
        }
        // Health first, then the death, in that order and through the same two
        // calls a fatal sword blow makes. A corpse at full health would make
        // `GetActorValue("Health")` and `IsDead()` disagree about the same
        // actor, and the HUD meter would show a live bar over a body.
        values.set(.health, to: 0, on: holder)
        guard let ragdoll = ragdollRuntime?() else { return false }
        return ragdoll.noteZeroHealth(of: key, killer: killer)
    }

    // MARK: - Perks

    @discardableResult
    public func addPerk(_ perk: ReferenceKey, to key: ReferenceKey) -> Bool {
        mutatePerks?(.add, perk, key) ?? false
    }

    @discardableResult
    public func removePerk(_ perk: ReferenceKey, from key: ReferenceKey) -> Bool {
        mutatePerks?(.remove, perk, key) ?? false
    }

    public func hasPerk(_ perk: ReferenceKey, on key: ReferenceKey) -> Bool? {
        guard let owned = perkOwnership?(key) else { return nil }
        return owned.contains(perk)
    }

    // MARK: - Skills

    @discardableResult
    public func advancePlayerSkill(
        _ advance: PapyrusSkillAdvance, at index: Int32, by magnitude: Float
    ) -> Bool {
        advanceSkill?(advance, index, magnitude) ?? false
    }

    // MARK: - Perk points

    public func playerPerkPoints() -> Int? {
        modifyPerkPoints.flatMap { $0(0) }
    }

    @discardableResult
    public func modifyPlayerPerkPoints(by delta: Int) -> Int? {
        modifyPerkPoints.flatMap { $0(delta) }
    }

    // MARK: - Private

    /// Whether `key` is in a fight: its behavior phase, not stored hostility.
    /// Searching counts. The player always reads false here, because the player's
    /// fight state is derived (`CombatLoopState.isPlayerInCombat`); a stated gap in
    /// docs/engine/papyrus-actor-natives.md.
    private func isActorInCombat(_ key: ReferenceKey) -> Bool {
        guard worldState.component(ActorDeathState.self, for: key)?.isDead != true
        else { return false }
        return (combatRuntime?()?.activity(of: key) ?? .notFighting) != .notFighting
    }

    /// The actor-value holder behind a reference: the player, or a resident
    /// ACHR resolved through the reference source. Nil for anything that is not
    /// an actor, which is what makes an `Actor` native called on a crate a
    /// tallied failure rather than a write to a crate's health.
    public func actorHolder(for key: ReferenceKey) -> ActorValueHolder? {
        if key == playerKey {
            return .player
        }
        guard let actor = references?.referenceEntry(key: key)?.placedActor else {
            return nil
        }
        return ActorValueHolder(
            key: key,
            subject: .actor(base: actor.base),
            cell: cellLocation(of: key)
        )
    }
}
