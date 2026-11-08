public import OpenSkyFormatsESM
public import OpenSkyInventoryInterface
public import OpenSkyMenusInterface

/// What the world adapters use of `ContainerMenuController`.
public protocol ContainerMenuPort: AnyObject {
    var container: InventoryHolder? { get }
    var isOpen: Bool { get }
    func open()
    func openInventory(of actor: ReferenceKey)
    var snapshot: ContainerMenuControlSnapshot { get }
    func target(_ holder: InventoryHolder, name: String, vendor: Vendor?, merchant: ReferenceKey?)
    func openBarter(
        with actor: ReferenceKey,
        vendorFaction override: ReferenceKey?
    ) -> String
    @discardableResult func openPickpocket(of actor: ReferenceKey) -> Bool

    func route(_ event: MenuInputEvent)

    var vendor: Vendor? { get }
}

/// The default arguments a protocol requirement cannot carry.
extension ContainerMenuPort {
    public func openBarter(with actor: ReferenceKey) -> String {
        openBarter(with: actor, vendorFaction: nil)
    }

    public func target(_ holder: InventoryHolder, name: String) {
        target(holder, name: name, vendor: nil, merchant: nil)
    }
}
