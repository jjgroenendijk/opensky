public import OpenSkyFactionsInterface
public import OpenSkyFormatsESM
public import OpenSkyInventoryInterface

/// What the world adapters use of `VendorCore`.
public protocol VendorCorePort {
    func vendor(memberships: ActorFactionState?) -> Vendor?
    func vendor(faction key: ReferenceKey) -> Vendor?
}
