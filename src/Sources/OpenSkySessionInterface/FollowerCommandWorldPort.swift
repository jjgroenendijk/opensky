public import OpenSkyFormatsESM
public import OpenSkyWorldInterface

/// What the world adapters use of `FollowerCommandWorldAdapter`.
public protocol FollowerCommandWorldPort: AnyObject {
    func commandTarget(_ key: ReferenceKey) -> FollowerCommandTarget?
    func enterCommandMode(_ follower: ReferenceKey)
    func favorStateChanged(_ actor: ReferenceKey, isDoingFavor: Bool)
}
