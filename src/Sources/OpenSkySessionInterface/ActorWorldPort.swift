public import OpenSkyCombatInterface
public import OpenSkyFormatsESM
public import OpenSkyGameData

/// What the world adapters use of `ActorWorldAdapter`.
public protocol ActorWorldPort: AnyObject {
    func actorValueHolder(for key: ReferenceKey) -> ActorValueHolder?
    func combatActor(key: ReferenceKey) -> CombatActorObservation?
    func combatActors() -> [CombatActorObservation]
    func displayName(of key: ReferenceKey, base: FormID) -> String?
    func isInCombat(_ key: ReferenceKey) -> Bool
    func nearestActorValueHolder() -> ActorValueHolder?
    func regeneratingHolders() -> [ActorValueHolder]
}
