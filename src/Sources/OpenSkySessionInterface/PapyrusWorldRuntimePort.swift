public import OpenSkyCombatInterface
public import OpenSkyConditions
public import OpenSkyFormatsESM
public import OpenSkyScriptingInterface

/// What the world adapters use of `PapyrusWorldRuntime`.
public protocol PapyrusWorldRuntimePort: AnyObject {
    associatedtype PapyrusScheduler: PapyrusSchedulerPort
    func handlesTrapHits(on trap: ReferenceKey) -> Bool
    func instanceStates() -> [PapyrusInstanceState]
    @discardableResult func queueActorDeath(actor: ReferenceKey, killer: ReferenceKey?) -> Int
    @discardableResult func queueAnimationEvent(sender: ReferenceKey, name: String) -> Int
    @discardableResult func queueEnterBleedout(actor: ReferenceKey) -> Int
    @discardableResult func queueFurnitureEvent(
        sitting: Bool,
        actor: ReferenceKey,
        furniture: ReferenceKey
    ) -> Int
    @discardableResult func queueGrab(of body: ReferenceKey, held: Bool) -> Int
    @discardableResult func queueOnHit(_ hit: ScriptHitEvent) -> Int
    @discardableResult func queuePlayerBowShot(
        weapon: FormID?,
        ammunition: FormID?,
        power: Float,
        sunGazing: Bool
    ) -> Int
    @discardableResult func queuePlayerFastTravelEnd(gameHours: Float) -> Int
    @discardableResult func queueRaceSwitchComplete(actor: ReferenceKey) -> Int
    @discardableResult func queueRead(on book: ReferenceKey) -> Int
    @discardableResult func queueSpellCast(_ spell: ReferenceKey, by caster: ReferenceKey) -> Int
    @discardableResult func queueTrapHit(_ hit: PapyrusTrapHit, on trap: ReferenceKey) -> Int
    @discardableResult func queueTrapHitStop(target: ReferenceKey, on trap: ReferenceKey) -> Int
    @discardableResult func queueWardHit(
        holder: ReferenceKey,
        caster: ReferenceKey,
        spell: ReferenceKey,
        status: Int32
    ) -> Int
    var scheduler: PapyrusScheduler { get }
    func scriptVariableResolution() -> ScriptVariableResolution
    func timerStates() -> [PapyrusTimerState]

    func waits(on key: ReferenceKey) -> [PapyrusWaitReadout]
    func instances(on key: ReferenceKey) -> [PapyrusInstanceReadout]
}
