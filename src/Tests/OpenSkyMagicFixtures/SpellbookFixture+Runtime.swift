// The spellbook runtime over the fixture records.

public import Foundation
public import OpenSkyFeaturesTesting
@testable import OpenSkyGameData
public import OpenSkyInventoryInterface
@testable public import OpenSkyMagic
@testable public import OpenSkyWorldState

extension SpellbookFixture {
    /// A spellbook runtime over a fresh store, plus the store so a suite can
    /// snapshot it.
    public static func runtime(
        store: WorldStateStore = WorldStateStore(),
        equipment: (any EquipmentAccess)? = nil,
        extraRecords: [Data] = []
    ) throws -> (SpellbookRuntime, WorldStateStore) {
        let index = try index(extraRecords: extraRecords)
        return (
            SpellbookRuntime(
                store: store,
                spells: SpellStore(index: index, effects: effectStore(index: index)),
                equipSlots: EquipSlotStore(index: index),
                equipment: equipment
            ),
            store
        )
    }
}
