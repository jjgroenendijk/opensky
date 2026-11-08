public import OpenSkyFormatsESM
public import OpenSkyInventoryInterface

/// What the world adapters use of `VendorCoordinator`.
public protocol VendorPort: AnyObject {
    associatedtype VendorCore: VendorCorePort
    var core: VendorCore { get }
    func counterparty(for actor: ReferenceKey, vendorFaction override: ReferenceKey?)
        -> Result<BarterCounterparty, BarterOpenRefusal>
    func vendor(of actor: ReferenceKey) -> Vendor?
}

/// The default arguments a protocol requirement cannot carry.
extension VendorPort {}
