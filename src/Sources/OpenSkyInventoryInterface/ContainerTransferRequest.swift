public import OpenSkyFormatsESM

/// One container move, so a transfer stays under the parameter cap.
public struct ContainerTransferRequest {
    public var transfer: ContainerTransfer
    public var item: FormID
    public var count: Int32 = 1
    public var name: String
    public var container: InventoryHolder
    public var vendor: Vendor?
    public var merchant: ReferenceKey?
    public var acceptingLess = false

    public init(
        _ transfer: ContainerTransfer, item: FormID, name: String,
        container: InventoryHolder, vendor: Vendor?
    ) {
        self.transfer = transfer
        self.item = item
        self.name = name
        self.container = container
        self.vendor = vendor
    }
}
