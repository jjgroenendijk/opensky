// The device-free half of the World > Inventory & Equipment surface
// (issue #180): every line the three sections show is a pure function of one
// snapshot, so it can be asserted without AppKit, without a Metal device and
// without a game install.

@testable import opensky
import Testing

struct InventoryEquipmentReadoutTests {
    private static func snapshot(
        playerStacks: [ItemStackReadout] = [],
        containerStacks: [ItemStackReadout] = [],
        hasOpenContainer: Bool = false,
        ownership: ReferenceOwnershipReadout? = nil,
        equipTarget: EquipmentTargetSelector = .nearestActor,
        inspection: EquipInspectReadout = .unresolved,
        enchantmentCache: EnchantmentCacheReadout = .empty
    ) -> InventoryEquipmentSnapshot {
        InventoryEquipmentSnapshot(
            isAvailable: true,
            hasOpenContainer: hasOpenContainer,
            openContainerName: hasOpenContainer ? "Chest" : nil,
            playerStacks: playerStacks,
            playerGold: 42,
            playerWeight: 9.25,
            containerStacks: containerStacks,
            containerGold: 500,
            targetOwnership: ownership,
            equipTarget: equipTarget,
            equipInspection: inspection,
            enchantmentCache: enchantmentCache,
            lastActionText: "No grant yet."
        )
    }

    private static func stacks(_ count: Int) -> [ItemStackReadout] {
        (0 ..< count).map {
            ItemStackReadout(
                item: FormID(UInt32(0x100 + $0)),
                count: Int32($0 + 1),
                name: "Item\($0)"
            )
        }
    }

    @Test
    func grantsTextNamesBothSidesAndTheLastAction() {
        let text = InventoryEquipmentReadout.grantsText(
            for: Self.snapshot(
                playerStacks: Self.stacks(2),
                containerStacks: Self.stacks(1),
                hasOpenContainer: true
            )
        )
        #expect(text.contains("Player: 2 stacks · weight 9.2 · gold 42"))
        #expect(text.contains("  1 × Item0"))
        #expect(text.contains("Container: Chest · gold 500"))
        #expect(text.hasSuffix("No grant yet."))
    }

    /// A closed container is a stated condition with the way to open one, not a
    /// blank line that reads like an empty chest.
    @Test
    func grantsTextStatesAClosedContainer() {
        let text = InventoryEquipmentReadout.grantsText(for: Self.snapshot())
        #expect(text.contains("Container: none open."))
        #expect(text.contains("World > HUD & Interaction > Items"))
        #expect(text.contains("  empty"))
    }

    /// A long inventory is truncated with a stated remainder, so the readout
    /// never silently shows part of one as the whole of it.
    @Test
    func grantsTextTruncatesWithAStatedRemainder() {
        let overLimit = InventoryEquipmentReadout.listedStackLimit + 3
        let text = InventoryEquipmentReadout.grantsText(
            for: Self.snapshot(playerStacks: Self.stacks(overLimit))
        )
        #expect(text.contains("  … 3 more"))
        #expect(!text.contains("Item\(overLimit - 1)"))
    }

    @Test
    func ownershipTextSeparatesNoTargetFromNoOwner() {
        #expect(
            InventoryEquipmentReadout.ownershipText(for: Self.snapshot())
                .hasPrefix("Target: none")
        )
        let unowned = InventoryEquipmentReadout.ownershipText(
            for: Self.snapshot(ownership: ReferenceOwnershipReadout(
                name: "Iron Sword", reference: FormID(0x700), owner: nil, factionRank: nil
            ))
        )
        #expect(unowned.contains("Owner: none — taking this is not theft."))
    }

    @Test
    func ownershipTextReportsOwnerRankAndTheEnforcedVerdict() {
        let owned = ReferenceOwnershipReadout(
            name: "Chest",
            reference: FormID(0x710),
            owner: FormID(0x3000),
            factionRank: 2,
            isTheft: true,
            bounty: 12
        )
        let text = InventoryEquipmentReadout.ownershipText(for: Self.snapshot(ownership: owned))
        #expect(text.contains("Owner: 00003000 — taking this is theft."))
        #expect(text.contains("Faction rank required: 2"))
        #expect(text.contains("Bounty if witnessed: 12 gold."))
        #expect(owned.isOwned)

        // An NPC-owned reference has no rank, and the line disappears rather
        // than printing a zero the data never authored.
        let noRank = ReferenceOwnershipReadout(
            name: "Chest",
            reference: FormID(0x710),
            owner: FormID(0x3000),
            factionRank: nil,
            isTheft: true
        )
        #expect(!InventoryEquipmentReadout.ownershipText(for: Self.snapshot(ownership: noRank))
            .contains("Faction rank"))
    }

    /// Ownership the reference does not carry itself: the cell claims it
    /// (issue #504), which is every crate in a vanilla shop.
    @Test
    func ownershipTextNamesTheCellWhenTheReferenceCarriesNoOwner() {
        let inherited = ReferenceOwnershipReadout(
            name: "Basket",
            reference: FormID(0x711),
            owner: nil,
            factionRank: nil,
            isTheft: true,
            bounty: 3
        )
        let text = InventoryEquipmentReadout.ownershipText(
            for: Self.snapshot(ownership: inherited)
        )
        #expect(text.contains("Owner: inherited from this cell — taking this is theft."))
        #expect(text.contains("Bounty if witnessed: 3 gold."))
        #expect(!inherited.isOwned)
    }

    /// A faction-owned reference the player ranks high enough in is not theft,
    /// even though it plainly has an owner.
    @Test
    func ownershipTextSaysNotTheftForPropertyTheActorMayUse() {
        let permitted = ReferenceOwnershipReadout(
            name: "Chest",
            reference: FormID(0x712),
            owner: FormID(0x3000),
            factionRank: 0,
            isTheft: false
        )
        let text = InventoryEquipmentReadout.ownershipText(
            for: Self.snapshot(ownership: permitted)
        )
        #expect(text.contains("Owner: 00003000 — taking this is not theft."))
        #expect(!text.contains("Bounty if witnessed"))
    }

    @Test
    func equipmentTextStatesAnUnresolvedOwner() {
        let text = InventoryEquipmentReadout.equipmentText(
            for: Self.snapshot(equipTarget: .player)
        )
        #expect(
            text == "Inspecting: Player\nNothing resolves that owner right now."
                + "\nEnchantment cache: 0 item(s), 0 resolved, 0 reused"
        )
    }

    @Test
    func equipmentTextNamesSourceSlotsAndSkips() {
        let inspection = EquipInspectReadout(
            name: "0x00003000",
            equipped: [
                EquippedItemReadout(item: FormID(0x300), name: "IronCuirass", occupancy: "body"),
                EquippedItemReadout(
                    item: FormID(0x200),
                    name: "IronSword",
                    occupancy: "right hand"
                )
            ],
            appearanceSkips: ["maskedByOutfit (00000310)"],
            usesRuntimeEquipment: true
        )
        let text = InventoryEquipmentReadout.equipmentText(
            for: Self.snapshot(inspection: inspection)
        )
        #expect(text.contains("Inspecting: Nearest NPC · 0x00003000"))
        #expect(text.contains("Appearance source: runtime equipped set"))
        #expect(text.contains("  IronCuirass · body"))
        #expect(text.contains("Appearance skips:\n  maskedByOutfit (00000310)"))
    }

    /// A clean resolution says so. "No skips" and "skips not read" must not
    /// look the same, and the plugin-outfit wording is what distinguishes an
    /// actor no equip has touched.
    @Test
    func equipmentTextStatesACleanPluginOutfit() {
        let inspection = EquipInspectReadout(
            name: "0x00003000", equipped: [], appearanceSkips: [], usesRuntimeEquipment: false
        )
        let text = InventoryEquipmentReadout.equipmentText(
            for: Self.snapshot(inspection: inspection)
        )
        #expect(text.contains("Appearance source: plugin outfit"))
        #expect(text.contains("Wearing: nothing"))
        #expect(text.contains("Appearance skips: none"))
    }

    /// The section states what the profile cache is doing (issue #489), which is
    /// what makes the per-frame reuse visible without a profiler.
    @Test
    func equipmentTextStatesTheEnchantmentCache() {
        let text = InventoryEquipmentReadout.equipmentText(
            for: Self.snapshot(
                inspection: EquipInspectReadout(
                    name: "0x00003000",
                    equipped: [],
                    appearanceSkips: [],
                    usesRuntimeEquipment: true
                ),
                enchantmentCache: EnchantmentCacheReadout(
                    itemCount: 2, resolvedCount: 2, reuseCount: 30
                )
            )
        )
        #expect(text.hasSuffix("Enchantment cache: 2 item(s), 2 resolved, 30 reused"))
    }

    /// Every readout degrades to the same stated non-answer with no runtime.
    @Test
    func unavailableSnapshotReadsTheSameEverywhere() {
        let snapshot = InventoryEquipmentSnapshot.unavailable
        let expected = snapshot.lastActionText
        #expect(InventoryEquipmentReadout.grantsText(for: snapshot) == expected)
        #expect(InventoryEquipmentReadout.ownershipText(for: snapshot) == expected)
        #expect(InventoryEquipmentReadout.equipmentText(for: snapshot) == expected)
    }

    @Test
    func grantTargetLabelsAreStable() {
        #expect(InventoryGrantTarget.allCases.map(\.label) == ["Player", "Open container"])
        #expect(InventoryEquipmentReadout.label(.player) == "Player")
        #expect(InventoryEquipmentReadout.label(.nearestActor) == "Nearest NPC")
    }
}
