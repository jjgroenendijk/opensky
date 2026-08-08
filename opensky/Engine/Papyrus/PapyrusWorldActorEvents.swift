// `OnHit`, `OnDying` and `OnDeath` dispatch (issue #375, roadmap item 15.8).
//
// Structurally this is `queueOnTriggerEnter` from PapyrusWorldTriggers.swift:
// one edge in the world becomes one queued event per script attached to the
// reference it happened to, at activation depth 0. A hit and a death are not
// activation chains — nothing a handler can call raises another hit — so they
// never consume the recursion cap that a player standing in a trigger volume
// would otherwise spend.
//
// A script attached to an actor that does not implement the handler is a
// counted no-op (`undefinedEventFunction`), not a fault, so queuing on every
// script of the actor is both free and correct.
//
// ## Exactly once
//
// Nothing here deduplicates, and nothing here needs to: the death latch does.
// `RagdollRuntime.noteZeroHealth(of:killer:)` writes `ActorDeathState` only for
// an actor not already recorded dead and raises the pair from inside that
// guard, so a per-frame sweep over every resident actor, a script `Kill`, and a
// fatal sword blow between them queue one `OnDying` and one `OnDeath` in total.
//
// ## `akKiller` and `akAggressor`
//
// Both are `ObjectReference`/`Actor` parameters and travel as world identities,
// so they become handles through `objectHandle(for:)` exactly as `akActionRef`
// does. A death nothing attributed — the sweep noticing a corpse whose killer
// no call named — passes `None`, which is what the Creation Kit documents the
// parameter's default to be.
//
// `akSource` and `akProjectile` are `Form` parameters naming a base record
// rather than a placed reference. A handle minted for one names the record and
// resolves to no script instance, so a handler may compare it and log it but
// cannot call a method on it. That is stated rather than hidden, and it is
// still more than the `None` the parameter would otherwise carry.

import Foundation

extension PapyrusWorldRuntime {
    /// Queues `OnHit(akAggressor, akSource, akProjectile, abPowerAttack,
    /// abSneakAttack, abBashAttack, abHitBlocked)` on every script attached to
    /// `hit.target`.
    ///
    /// Parameter order and meaning are the Creation Kit wiki's
    /// (<https://www.creationkit.com/index.php?title=OnHit_-_ObjectReference>).
    /// The event is declared on `ObjectReference`, not on `Actor`, so it
    /// reaches a scripted crate the same way it reaches a scripted bandit.
    ///
    /// - Returns: how many events were queued.
    @discardableResult
    func queueOnHit(_ hit: ScriptHitEvent) -> Int {
        queueActorEvent(
            Self.onHitEventName,
            on: hit.target,
            arguments: [
                .object(objectHandle(for: hit.aggressor)),
                formValue(hit.source),
                formValue(hit.projectile),
                .boolean(hit.isPowerAttack),
                .boolean(hit.isSneakAttack),
                .boolean(hit.isBashAttack),
                .boolean(hit.isBlocked)
            ]
        )
    }

    /// Queues `OnDying(akKiller)` then `OnDeath(akKiller)` on every script
    /// attached to `actor`.
    ///
    /// Both, in that order, and both from the same call. The Creation Kit
    /// distinguishes them by *when* they fire — "when the actor begins dying"
    /// against "when the actor finishes dying" — and this engine has one death
    /// moment: the latch. Firing them a variable number of frames apart would
    /// mean inventing a dying duration the ragdoll hand-off does not define, so
    /// they are adjacent in the queue instead. `OnDying` is still ahead of
    /// `OnDeath` for every instance, which is the ordering script code relies
    /// on.
    ///
    /// - Returns: how many events were queued, across both names.
    @discardableResult
    func queueActorDeath(actor: ReferenceKey, killer: ReferenceKey?) -> Int {
        let arguments: [PapyrusValue] = [
            killer.map { .object(objectHandle(for: $0)) } ?? .none
        ]
        return queueActorEvent(Self.onDyingEventName, on: actor, arguments: arguments)
            + queueActorEvent(Self.onDeathEventName, on: actor, arguments: arguments)
    }

    /// Instance iteration is `instancesByKey.keys.sorted()`, the same
    /// deterministic order `queueOnActivate` uses, so a reference carrying
    /// several scripts always queues them the same way.
    private func queueActorEvent(
        _ functionName: String,
        on reference: ReferenceKey,
        arguments: [PapyrusValue]
    ) -> Int {
        var queued = 0
        for key in instancesByKey.keys.sorted() where key.reference == reference {
            enqueue(PapyrusScriptEvent(
                target: key,
                functionName: functionName,
                arguments: arguments,
                activationDepth: 0
            ))
            queued += 1
        }
        return queued
    }

    /// A base record as a `Form` argument: an opaque handle when this session
    /// can name the FormID, Papyrus `None` when it cannot and when the caller
    /// had none to give.
    private func formValue(_ formID: FormID?) -> PapyrusValue {
        guard
            let formID,
            let key = formIDResolver.flatMap({ ReferenceKey.resolve(formID, using: $0) })
        else {
            return .none
        }
        return .object(objectHandle(for: key))
    }
}
