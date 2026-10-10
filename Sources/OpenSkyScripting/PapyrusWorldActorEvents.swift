// `OnHit`, `OnDying` and `OnDeath` dispatch: one event per attached script at depth 0,
// like `queueOnTriggerEnter`. The death latch in `RagdollRuntime.noteZeroHealth` makes
// death fire once. Killer and aggressor become handles via `objectHandle(for:)`, or
// `None` when unknown; `akSource` and `akProjectile` name base records, so methods on
// them fail. Handlers a script lacks are counted no-ops.

import Foundation
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

extension PapyrusWorldRuntime {
    /// Queues `OnHit` with the Creation Kit's seven parameters
    /// (<https://www.creationkit.com/index.php?title=OnHit_-_ObjectReference>) on each
    /// script of `hit.target`. Declared on `ObjectReference`, so crates get it too.
    /// Returns the count.
    @discardableResult
    public func queueOnHit(_ hit: ScriptHitEvent) -> Int {
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

    /// Queues `OnDying(akKiller)` then `OnDeath(akKiller)` on each script of `actor`, from
    /// one call: there is one death moment, and inventing a dying duration is worse.
    /// `OnDying` still comes first. Returns the count across both names.
    @discardableResult
    public func queueActorDeath(actor: ReferenceKey, killer: ReferenceKey?) -> Int {
        let arguments: [PapyrusValue] = [
            killer.map { .object(objectHandle(for: $0)) } ?? .none
        ]
        return queueActorEvent(Self.onDyingEventName, on: actor, arguments: arguments)
            + queueActorEvent(Self.onDeathEventName, on: actor, arguments: arguments)
    }

    /// Queues `OnRaceSwitchComplete()` on each script of `actor`, after the race menu
    /// changed the player's race. Returns the count.
    @discardableResult
    public func queueRaceSwitchComplete(actor: ReferenceKey) -> Int {
        queueActorEvent("OnRaceSwitchComplete", on: actor, arguments: [])
    }

    /// Queues `OnPackageStart(akNewPackage)`, `OnPackageEnd(akOldPackage)`, or
    /// `OnPackageChange(akOldPackage)` on each script of `actor`. Returns the count.
    @discardableResult
    public func queuePackageEvent(
        _ functionName: String, package: FormID, actor: ReferenceKey
    ) -> Int {
        queueActorEvent(functionName, on: actor, arguments: [formValue(package)])
    }

    /// Instance iteration is in `PapyrusInstanceKey` order, the same
    /// deterministic order `queueOnActivate` uses, so a reference carrying
    /// several scripts always queues them the same way.
    private func queueActorEvent(
        _ functionName: String,
        on reference: ReferenceKey,
        arguments: [PapyrusValue]
    ) -> Int {
        var queued = 0
        for key in instanceKeys(on: reference) {
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
