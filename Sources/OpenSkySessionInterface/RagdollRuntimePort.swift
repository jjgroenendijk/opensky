public import OpenSkyCombatInterface
public import OpenSkyFormatsESM
public import OpenSkyPhysics

/// What the world adapters use of `RagdollRuntime`.
public protocol RagdollRuntimePort: DeathReporting {
    @discardableResult func activate(_ key: ReferenceKey, instant: Bool) -> Bool
    func addLink(_ link: PhysicsLink) -> Bool
    func addPin(_ pin: PhysicsPin) -> Bool
    func removeConstraints(_ first: PhysicsLinkEnd, _ second: PhysicsLinkEnd) -> Bool
    func reset()
    func solveLinks(to loose: inout DynamicBodyWorld, frameTime: Float)
    @discardableResult func trim(to limit: Int) -> Int
    var world: RagdollWorld { get }

    func hasBody(_ end: PhysicsLinkEnd) -> Bool
    func ragdollsForConstraint(_ key: ReferenceKey) -> Bool
}
