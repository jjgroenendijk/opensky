public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyMagicInterface
public import OpenSkyPhysics

/// What the world adapters use of `HazardWorldAdapter`.
public protocol HazardWorldPort: AnyObject {
    func hazardCandidates() -> [MeleeTarget]
    var store: HazardStore? { get }
    /// The hazard `key` names, resolved from the store.
    func hazardSpec(for key: ReferenceKey) -> HazardSpec?
    /// The model a spawned hazard of `key` draws.
    func hazardModelPath(for key: ReferenceKey) -> String?
}
