public import OpenSkyFormatsESM
public import OpenSkyWorldInterface

/// What the world adapters use of `FurnitureCoordinator`.
public protocol FurniturePort: AnyObject {
    associatedtype FurnitureSeatLedger: FurnitureSeatLedgerPort
    func advance()
    var exits: [ReferenceKey: FurnitureOccupancy] { get }
    @discardableResult func greet(_ actor: ReferenceKey) -> Bool
    func isInUse(_ furniture: ReferenceKey, marker: Int?, ignoringReserved: Bool) -> Bool
    func isLeavingSeat(_ actor: ReferenceKey) -> Bool
    var ledger: FurnitureSeatLedger { get }
    func nearestFurniture(to actor: ReferenceKey) -> ReferenceKey?
    var occupancies: [ReferenceKey: FurnitureOccupancy] { get }
    func releaseReservations(of actor: ReferenceKey)
    func reserve(
        in furniture: ReferenceKey,
        for actor: ReferenceKey,
        animation: UInt16?
    ) -> PackageSeat?
    func sandboxSeat(for actor: ReferenceKey, in request: SandboxSeatRequest) -> PackageSeat?
    func setSittingRotation(degrees: Float)
    @discardableResult func sit(_ actor: ReferenceKey, in seat: PackageSeat) -> FurnitureOccupancy?
    var sittingRotation: Float { get }
    @discardableResult func stand(_ actor: ReferenceKey) -> Bool
    func use(_ furniture: ReferenceKey, by actor: ReferenceKey)
        -> Result<FurnitureOccupancy, FurnitureUseRefusal>
    @discardableResult func vacate(_ actor: ReferenceKey) -> FurnitureOccupancy?
}
