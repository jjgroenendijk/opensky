// The session port calls, each answered by the part that owns it.

import Foundation
public import OpenSkyCombatInterface
public import OpenSkyConditions
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyScriptingInterface
import OpenSkyWorldInterface
public import OpenSkyWorldState

extension PapyrusWorldRuntime {
    public func instanceStates() -> [PapyrusInstanceState] {
        lifecycle.instanceStates()
    }

    public func timerStates() -> [PapyrusTimerState] {
        lifecycle.timerStates()
    }

    @discardableResult
    public func queueOnHit(_ hit: ScriptHitEvent) -> Int {
        scriptEvents.queueOnHit(hit)
    }

    @discardableResult
    public func queueActorDeath(actor: ReferenceKey, killer: ReferenceKey?) -> Int {
        scriptEvents.queueActorDeath(actor: actor, killer: killer)
    }

    @discardableResult
    public func queueEnterBleedout(actor: ReferenceKey) -> Int {
        scriptEvents.queueEnterBleedout(actor: actor)
    }

    @discardableResult
    public func queueWardHit(
        holder: ReferenceKey, caster: ReferenceKey, spell: ReferenceKey, status: Int32
    ) -> Int {
        scriptEvents.queueWardHit(holder: holder, caster: caster, spell: spell, status: status)
    }

    @discardableResult
    public func queueRead(on book: ReferenceKey) -> Int {
        scriptEvents.queueRead(on: book)
    }

    @discardableResult
    public func queueGrab(of body: ReferenceKey, held: Bool) -> Int {
        scriptEvents.queueGrab(of: body, held: held)
    }

    @discardableResult
    public func queueRaceSwitchComplete(actor: ReferenceKey) -> Int {
        scriptEvents.queueRaceSwitchComplete(actor: actor)
    }

    @discardableResult
    public func queueAnimationEvent(sender: ReferenceKey, name: String) -> Int {
        scriptEvents.queueAnimationEvent(sender: sender, name: name)
    }

    @discardableResult
    public func queuePlayerFastTravelEnd(gameHours: Float) -> Int {
        scriptEvents.queuePlayerFastTravelEnd(gameHours: gameHours)
    }

    @discardableResult
    public func queueFurnitureEvent(
        sitting: Bool, actor: ReferenceKey, furniture: ReferenceKey
    ) -> Int {
        scriptEvents.queueFurnitureEvent(sitting: sitting, actor: actor, furniture: furniture)
    }

    @discardableResult
    public func queueSpellCast(_ spell: ReferenceKey, by caster: ReferenceKey) -> Int {
        scriptEvents.queueSpellCast(spell, by: caster)
    }

    @discardableResult
    public func queuePlayerBowShot(
        weapon: FormID?, ammunition: FormID?, power: Float, sunGazing: Bool
    ) -> Int {
        scriptEvents.queuePlayerBowShot(
            weapon: weapon,
            ammunition: ammunition,
            power: power,
            sunGazing: sunGazing
        )
    }

    public func handlesTrapHits(on trap: ReferenceKey) -> Bool {
        scriptEvents.handlesTrapHits(on: trap)
    }

    @discardableResult
    public func queueTrapHit(_ hit: PapyrusTrapHit, on trap: ReferenceKey) -> Int {
        scriptEvents.queueTrapHit(hit, on: trap)
    }

    @discardableResult
    public func queueTrapHitStop(target: ReferenceKey, on trap: ReferenceKey) -> Int {
        scriptEvents.queueTrapHitStop(target: target, on: trap)
    }

    public func waits(on key: ReferenceKey) -> [PapyrusWaitReadout] {
        timers.waits(on: key)
    }

    public func instances(on key: ReferenceKey) -> [PapyrusInstanceReadout] {
        timers.instances(on: key)
    }

    public func scriptVariableResolution() -> ScriptVariableResolution {
        readouts.scriptVariableResolution()
    }

    /// The session-stable handle for `key`.
    public func objectHandle(for key: ReferenceKey) -> PapyrusObjectHandle {
        activationRuns.objectHandle(for: key)
    }

    /// World identity behind a handle, or nil for a handle this runtime never handed out.
    public func referenceKey(for handle: PapyrusObjectHandle) -> ReferenceKey? {
        activationRuns.referenceKey(for: handle)
    }

    /// Attaches the scripts on a cell's references as the cell enters the scene.
    public func attach(
        cell: CellSceneLocation,
        references: RuntimeReferenceIndex,
        formIDResolver: FormIDResolver,
        firstIntegration: Bool
    ) {
        lifecycle.attach(
            cell: cell, references: references, formIDResolver: formIDResolver,
            firstIntegration: firstIntegration
        )
    }

    /// Retires the scripts on a cell's references as the cell leaves the scene.
    public func detach(cell: CellSceneLocation) {
        lifecycle.detach(cell: cell)
    }

    @discardableResult
    public func registerUpdateTimer(
        handle: PapyrusObjectHandle, slot: PapyrusUpdateTimerSlot, interval: Double
    ) -> Bool {
        timers.registerUpdateTimer(handle: handle, slot: slot, interval: interval)
    }

    @discardableResult
    public func unregisterUpdateTimers(
        handle: PapyrusObjectHandle, family: PapyrusUpdateTimerFamily
    ) -> Bool {
        timers.unregisterUpdateTimers(handle: handle, family: family)
    }
}
