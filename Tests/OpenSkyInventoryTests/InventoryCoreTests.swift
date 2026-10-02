// The inventory decisions with plain values: names, slot listings, grant
// checks and outcome sentences. No store and no world.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyInventory
@testable import OpenSkyInventoryInterface
import Testing

struct InventoryCoreTests {
    @Test func anItemNoIndexDescribesIsNamedByItsFormID() {
        let item = FormID(0x1234)
        #expect(InventoryCore.displayName(of: item, definition: nil) == item.description)
    }

    @Test func anActorIsNamedByItsKeyAndBase() {
        let key = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x900)
        let actor = InventoryHolder(key: key, owner: .actor(base: FormID(0x50)), cell: nil)
        let chest = InventoryHolder(key: key, owner: .container(base: FormID(0x60)), cell: nil)
        #expect(InventoryCore.actorName(actor) == "\(key.description) (base \(FormID(0x50)))")
        #expect(InventoryCore.actorName(chest) == key.description)
    }

    @Test func slotListingsNameSlotsHandsAndUnnamedBits() {
        #expect(InventoryCore.describe(.none) == "no slots")
        #expect(InventoryCore.describe(EquipmentOccupancy(hands: .rightHand)) == "right hand")
        #expect(InventoryCore.describe(EquipmentOccupancy(slots: .body)) == "body")
        // Slot 44 has no name but must still show.
        let modSlot = BodySlots(rawValue: 1 << 14)
        #expect(InventoryCore.describe(EquipmentOccupancy(slots: modSlot)) == "raw 0x4000")
    }

    @Test func aGrantNeedsAPositiveCountAndAKnownItem() {
        let item = FormID(0x40)
        #expect(InventoryCore.grantRefusal(item: item, count: 0, isKnown: true)?
            .contains("is not a stack") == true)
        #expect(InventoryCore.grantRefusal(item: item, count: 1, isKnown: false)?
            .contains("no loaded plugin describes") == true)
        #expect(InventoryCore.grantRefusal(item: item, count: 1, isKnown: true) == nil)
    }

    @Test func outcomeSentencesNameWhatHappened() {
        #expect(InventoryCore.equipSentence(
            changed: true, item: "Sword", target: "the player", unequipped: ["Axe", "Mace"]
        ) == "Equipped Sword on the player, unequipped Axe, Mace.")
        #expect(InventoryCore.equipSentence(
            changed: false, item: "Sword", target: "the player", unequipped: []
        ) == "Sword was already equipped on the player.")
        #expect(InventoryCore.takeSentence(item: "Ring", bounty: 0) == "Took Ring.")
        #expect(InventoryCore.takeSentence(item: "Ring", bounty: 25) == "Stole Ring — 25 bounty.")
    }

    @Test func theFirstEquippableStackSkipsWornAndUnwearableItems() {
        let potion = FormID(0x10)
        let helmet = FormID(0x20)
        let cuirass = FormID(0x30)
        let state = ReferenceInventoryState(
            stacks: [
                InventoryStack(item: potion, count: 1),
                InventoryStack(item: helmet, count: 1),
                InventoryStack(item: cuirass, count: 1)
            ],
            equipped: [helmet]
        )
        let found = InventoryCore.firstEquippable(in: state) {
            $0 == potion ? .none : EquipmentOccupancy(slots: .body)
        }
        #expect(found == cuirass)
    }
}
