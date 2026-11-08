public import OpenSkyFormatsESM
public import OpenSkyScriptingInterface

/// What the world adapters use of `VehicleWorldAdapter`.
public protocol VehicleWorldPort: AnyObject, PapyrusActorAIBridge {
    func detach(_ follower: ReferenceKey)
    func handleBodyEvent(_ name: String, from actor: ReferenceKey)
    func handleIdleAnimationEvent(_ name: String, from actor: ReferenceKey)
    var isPlayerAIDriven: Bool { get }
    func setSittingRotation(degrees: Float)
    func vehicleFormID(of key: ReferenceKey) -> UInt32?
    func vehicleHasBone(_ key: ReferenceKey, named bone: String) -> Bool
    var vehicles: any VehiclePort { get }
}
