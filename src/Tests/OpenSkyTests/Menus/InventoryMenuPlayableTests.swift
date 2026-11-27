// A weapon flagged non-playable gets no inventory row, and its definition says so.

import Foundation
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
@testable import OpenSkyInventoryInterface
@testable import OpenSkyMenus
@testable import OpenSkyWorldState
import Testing

struct InventoryMenuPlayableTests {
    private let claws = FormID(0x0000_0800)
    private let dagger = FormID(0x0000_0810)

    private func weapon(_ id: FormID, editorID: String, flags: UInt16) -> Data {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring(editorID))
        fields += ESMFixture.field(
            "DATA", InventoryFixture.weaponData(value: 10, weight: 2, damage: 4)
        )
        fields += ESMFixture.field("DNAM", InventoryFixture.weaponDNAM(
            animation: 2, speed: 1, reach: 1, flags: flags
        ))
        return ESMFixture.record("WEAP", formID: id.rawValue, data: fields)
    }

    private func items() throws -> ItemDefinitionStore {
        try ItemDefinitionStore(file: ESMFixture.plugin(records: [
            weapon(claws, editorID: "UnarmedClaws", flags: 0x0080),
            weapon(dagger, editorID: "IronDagger", flags: 0)
        ]))
    }

    @Test func nonPlayableWeaponHasNoRow() throws {
        let items = try items()
        #expect(items.definition(claws)?.isPlayable == false)
        #expect(items.definition(dagger)?.isPlayable == true)
        let model = InventoryMenuModel.build(
            inventory: ReferenceInventoryState(stacks: [
                InventoryStack(item: claws, count: 1),
                InventoryStack(item: dagger, count: 1)
            ]),
            items: items
        )
        #expect(model.allEntries.map(\.item) == [dagger])
    }
}
