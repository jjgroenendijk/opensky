// `PapyrusWorldActorBridge` conformance (issues #375 and #424, roadmap items
// 15.8 and 16.7): where the `Actor` natives meet 15.3's actor values, 15.6's
// death latch and 16.7's fights.
//
// Split out of `PapyrusWorldStateBridge.swift` for the reason the quest half is
// split out: that file is already at its size shape, and a reader chasing "what
// does `DamageActorValue` really do" should land on one screen that says so.
//
// ## Nothing here writes around the subsystems that own the state
//
// Values go through `ActorValueRuntime`, so the clamp, the journal, the dirty
// counts and the save see a script's damage exactly as they see a sword's.
// Deaths go through `RagdollRuntime.noteZeroHealth(of:killer:)`, so a scripted
// kill raises the same census-named graph events, spawns the same ragdoll and
// fires the same `OnDeath` as a fatal blow. `StartCombat` and `StopCombat` go
// through `CombatLoopRuntime`, so a script's fight is the same fight the player
// can walk into: it writes hostility through the world-state store, engages the
// same behavior machine, and ends by handing the actor back to its package.
//
// ## Why the collaborators are closures
//
// The actor-value runtime and the ragdoll runtime are built by their own
// wiring steps, and the order those steps run in is the controller's business
// rather than this bridge's. Holding a closure instead of a reference means the
// bridge is correct whichever order the session wires, and means a test can
// supply one subsystem without standing up the other.
//
// Documented in docs/engine/papyrus-vm.md.

import Foundation

extension PapyrusWorldStateBridge {
    // MARK: - Reading

    func actorState(for key: ReferenceKey) -> PapyrusActorState? {
        guard let values = actorValueRuntime?(), let holder = actorHolder(for: key) else {
            return nil
        }
        return PapyrusActorState(
            current: values.current(of: holder),
            maximums: values.baseline(of: holder).maximums,
            isDead: worldState.component(ActorDeathState.self, for: key)?.isDead ?? false,
            isInCombat: isActorInCombat(key),
            combatActivity: combatRuntime?()?.activity(of: key) ?? .notFighting,
            weaponDrawState: weaponDrawState?(key),
            general: values.state(of: holder).general,
            generalBaseline: values.baseline(of: holder).general,
            isPlayer: key == playerKey
        )
    }

    // MARK: - Writing

    @discardableResult
    func damageActorValue(
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
    func restoreActorValue(
        at index: Int32, by amount: Float, on key: ReferenceKey
    ) -> PapyrusActorState? {
        guard let values = actorValueRuntime?(), let holder = actorHolder(for: key) else {
            return nil
        }
        guard values.restore(at: index, by: amount, on: holder) else { return nil }
        return actorState(for: key)
    }

    @discardableResult
    func startActorCombat(_ key: ReferenceKey, target: ReferenceKey) -> Bool {
        combatRuntime?()?.startCombat(key, with: target) ?? false
    }

    @discardableResult
    func stopActorCombat(_ key: ReferenceKey) -> Bool {
        combatRuntime?()?.stopCombat(key) ?? false
    }

    @discardableResult
    func killActor(_ key: ReferenceKey, killer: ReferenceKey?) -> Bool {
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

    // MARK: - Private

    /// Whether `key` is actually in a fight, which is its 16.7 behavior phase
    /// rather than its stored hostility: an actor that hates the player but has
    /// not noticed them is not in combat, and neither is one that gave up.
    /// Searching counts, because a searching actor has not left the fight.
    ///
    /// The player is never "in combat" by this reading, because hostility is
    /// stored per NPC and describes how that NPC regards the player. Whether
    /// the *player* is in a fight is `CombatLoopState.isPlayerInCombat`, which
    /// is derived from every resident actor rather than stored on one, and
    /// answering it here would mean holding the combat runtime as well.
    /// `Game.GetPlayer().IsInCombat()` therefore reads false in a fight, which
    /// is a stated gap rather than a hidden one — see docs/engine/papyrus-vm.md.
    private func isActorInCombat(_ key: ReferenceKey) -> Bool {
        guard worldState.component(ActorDeathState.self, for: key)?.isDead != true
        else { return false }
        return (combatRuntime?()?.activity(of: key) ?? .notFighting) != .notFighting
    }

    /// The actor-value holder behind a reference: the player, or a resident
    /// ACHR resolved through the reference source. Nil for anything that is not
    /// an actor, which is what makes an `Actor` native called on a crate a
    /// tallied failure rather than a write to a crate's health.
    private func actorHolder(for key: ReferenceKey) -> ActorValueHolder? {
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
