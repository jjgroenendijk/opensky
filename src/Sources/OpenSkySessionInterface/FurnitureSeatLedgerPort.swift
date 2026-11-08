public import OpenSkyFormatsESM

/// What the world adapters use of `FurnitureSeatLedger`.
public protocol FurnitureSeatLedgerPort {
    func holders(of furniture: ReferenceKey) -> [Int: ReferenceKey]
}
