// An `InventoryAccess` over a dictionary, for the jail tests. Stolen flags and
// equipment are not modelled.

@testable import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyInventoryInterface

@MainActor
final class FakeCrimeInventory: InventoryAccess {
    let baselines: InventoryBaselineResolver
    let goldFormID = InventoryBaselineFixture.gold
    var counts: [ReferenceKey: [FormID: Int32]] = [:]

    init() throws {
        baselines = try InventoryBaselineFixture.resolver()
    }

    func inventory(of holder: InventoryHolder) -> ReferenceInventoryState {
        let stacks = (counts[holder.key] ?? [:]).sorted { $0.key.rawValue < $1.key.rawValue }
            .map { InventoryStack(item: $0.key, count: $0.value) }
        return ReferenceInventoryState(stacks: stacks)
    }

    func count(of item: FormID, in holder: InventoryHolder) -> Int32 {
        counts[holder.key]?[item] ?? 0
    }

    func goldCount(of holder: InventoryHolder) -> Int32 {
        count(of: goldFormID, in: holder)
    }

    @discardableResult
    func add(_ item: FormID, count: Int32, to holder: InventoryHolder) throws
        -> ReferenceInventoryState
    {
        counts[holder.key, default: [:]][item, default: 0] += count
        return inventory(of: holder)
    }

    @discardableResult
    func remove(_ item: FormID, count: Int32, from holder: InventoryHolder) throws
        -> ReferenceInventoryState
    {
        let held = self.count(of: item, in: holder)
        guard held >= count else { throw InventoryError.insufficientCount(
            item: item, owner: holder.key, requested: count, available: held
        ) }
        counts[holder.key]?[item] = held == count ? nil : held - count
        return inventory(of: holder)
    }

    /// Every copy is plain: jail tests never temper or fill one.
    func copies(of item: FormID, in holder: InventoryHolder) -> [ItemCopy] {
        Array(repeating: .plain, count: Int(count(of: item, in: holder)))
    }

    func editCopy(
        of _: FormID,
        in _: InventoryHolder,
        where _: (ItemCopy) -> Bool,
        _: (inout ItemCopy) -> Void
    ) -> Bool {
        false
    }

    func confiscateStolen(
        from _: InventoryHolder,
        to _: InventoryHolder
    ) throws -> [InventoryStack] {
        []
    }
}
