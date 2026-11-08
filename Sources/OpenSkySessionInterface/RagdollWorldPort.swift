public import OpenSkyCombatInterface
public import OpenSkyFormatsESM
public import OpenSkyGameData

/// What the world adapters use of `RagdollWorldAdapter`.
public protocol RagdollWorldPort: AnyObject {
    func holder(of key: ReferenceKey) -> ActorValueHolder?
    func zeroHealthOutcome(of key: ReferenceKey, killer: ReferenceKey?) -> ZeroHealthOutcome
}
