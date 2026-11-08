public import OpenSkyFormatsESM

/// What the world adapters use of `DragonFlightWorldAdapter`.
public protocol DragonFlightWorldPort: AnyObject {
    func actorFliesPackages(_ actor: ReferenceKey) -> Bool
    var flyingStates: [ReferenceKey: Int32] { get }
    func isFlying(_ actor: ReferenceKey) -> Bool
}
