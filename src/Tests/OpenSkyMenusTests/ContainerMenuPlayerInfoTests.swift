import OpenSkyFormatsESM
import OpenSkyFormatsSWF
import OpenSkyInventoryInterface
@testable import OpenSkyMenus
import Testing

struct ContainerMenuPlayerInfoTests {
    /// The bar's damage is the best equipped weapon's; its armour sums the worn pieces.
    /// Items carried but not worn count for neither.
    @Test func thePlayerInfoReadsOnlyEquippedCards() {
        let cards: [FormID: InventoryItemCard] = [
            FormID(0x10): InventoryItemCard(
                layout: .weapon, name: "Iron Sword", kind: "Weapon", value: 25, weight: 9,
                damage: 7
            ),
            FormID(0x11): InventoryItemCard(
                layout: .weapon, name: "Steel Sword", kind: "Weapon", value: 45, weight: 10,
                damage: 8
            ),
            FormID(0x20): InventoryItemCard(
                layout: .armour, name: "Hide Helmet", kind: "Light", value: 20, weight: 2,
                armourRating: 10.4
            ),
            FormID(0x21): InventoryItemCard(
                layout: .armour, name: "Hide Boots", kind: "Light", value: 10, weight: 1,
                armourRating: 5
            )
        ]
        let entries = [(0x10, true), (0x11, false), (0x20, true), (0x21, true)].map {
            InventoryMenuEntry(
                item: FormID(UInt32($0.0)), name: "", count: 1, weight: 1, value: 1,
                isEquipped: $0.1, family: nil
            )
        }
        let info = ContainerMenuMovieBridge.playerInfo(of: entries) { cards[$0] }
        #expect(info["damage"] == .number(7))
        #expect(info["armor"] == .number(15))
        #expect(info["warmth"] == nil)
    }
}
