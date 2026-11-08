public import OpenSkyGameData
public import OpenSkyPhysics

/// What the world adapters use of `HazardWorldAdapter`.
public protocol HazardWorldPort: AnyObject {
    func hazardCandidates() -> [MeleeTarget]
    var store: HazardStore? { get }
}
