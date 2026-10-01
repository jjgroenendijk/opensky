// The spellbook runtime over the fixture records.

@testable import OpenSkyGameData
import OpenSkyInventoryInterface
@testable import OpenSkyMagic
import OpenSkyMagicTesting
@testable import OpenSkyWorldState

extension SpellbookFixture {
    /// A spellbook runtime over a fresh store, plus the store so a suite can
    /// snapshot it.
    public static func runtime(
        store: WorldStateStore = WorldStateStore(),
        equipment: (any EquipmentAccess)? = nil
    ) throws -> (SpellbookRuntime, WorldStateStore) {
        let index = try index()
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
