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

    /// With the player's shown values, a card and the bar take them over the base;
    /// an item with no shown value keeps its base, and the bonus adds to the armour.
    @Test func shownValuesReplaceTheBase() {
        let cards: [FormID: InventoryItemCard] = [
            FormID(0x10): InventoryItemCard(
                layout: .weapon, name: "Iron Sword", kind: "Weapon", value: 25, weight: 9,
                damage: 7
            ),
            FormID(0x20): InventoryItemCard(
                layout: .armour, name: "Hide Helmet", kind: "Light", value: 20, weight: 2,
                armourRating: 10
            )
        ]
        let stats = ShownGearStats(
            damage: { item, level in item == FormID(0x10) ? 9 + Int(level) : nil },
            armour: { _, _ in nil },
            armourBonus: 40
        )
        var sword = InventoryMenuEntry(
            item: FormID(0x10), name: "Fine Iron Sword", count: 1, weight: 9, value: 30,
            isEquipped: true, family: nil
        )
        sword.copy = ItemCopy(level: 1)
        let helmet = InventoryMenuEntry(
            item: FormID(0x20), name: "", count: 1, weight: 2, value: 20,
            isEquipped: true, family: nil
        )

        let card = InventoryMenuMovieBridge.card(for: sword, stats: stats) { cards[$0] }
        let info = ContainerMenuMovieBridge.playerInfo(of: [sword, helmet], stats: stats) {
            cards[$0]
        }

        #expect(card?.damage == 10)
        #expect(info["damage"] == .number(10))
        #expect(info["armor"] == .number(50))
        #expect(ShownGearStats.base.damage(FormID(0x10), 0) == nil)
    }

    /// The bar reads the values from the menu clip's player info object.
    @MainActor @Test func publishingStoresTheInfoOnTheMenuClip() throws {
        let runtime = try MenuMovieCallLog.emptyRuntime()
        let menu = SWFDisplayObject(content: .clip(nil))
        menu.name = "Menu_mc"
        runtime.root.addChild(menu, atDepth: 1)

        ContainerMenuMovieBridge.publishPlayerInfo(["damage": .number(9)], runtime: runtime)

        guard
            case let .object(info)? = menu.object.ownProperty("PlayerInfoObj")?.value
        else {
            Issue.record("no player info object")
            return
        }
        #expect(info.ownProperty("damage")?.value == .number(9))
    }
}
