import OpenSkyFactionsInterface
public import OpenSkyFormatsESM
public import OpenSkyInventoryInterface

/// What the world adapters use of `VendorCore`.
public protocol VendorCorePort {
    func vendor(faction key: ReferenceKey) -> Vendor?
}
