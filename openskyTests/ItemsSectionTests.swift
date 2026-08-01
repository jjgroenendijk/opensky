// World > HUD & Interaction > Items section (issue #177, roadmap item 12.1.3):
// the accessibility-id contract, the readout spelling, and that every control
// reaches the provider. `make test-ui` is TCC-blocked on this machine, so the
// ids are pinned here as literal assertions.

import AppKit
@testable import opensky
import Testing

/// Records what the section asked the engine to do, and answers with whatever
/// reading the test set. Shared with `DestinationRegistryTests`, which holds one
/// of these so a registry-level panel build and a button press are observed
/// through the same fake.
@MainActor
final class FakeItemProvider: ItemControlProviding {
    var itemControlSnapshot = ItemControlSnapshot.unavailable
    /// Every action a control ran, in order.
    private(set) var actions: [String] = []

    @discardableResult
    func takeInteractionTarget() -> String {
        record("take")
    }

    @discardableResult
    func openInteractionTargetContainer() -> String {
        record("search")
    }

    @discardableResult
    func takeAllFromOpenContainer() -> String {
        record("takeAll")
    }

    @discardableResult
    func closeOpenContainer() -> String {
        record("close")
    }

    @discardableResult
    func dropPlayerItem(_ item: FormID?, count: Int32) -> String {
        record("drop \(item?.description ?? "first")×\(count)")
    }

    @discardableResult
    func equipItem(_ item: FormID?, on target: EquipmentTargetSelector) -> String {
        record("equip \(item?.description ?? "first") on \(target)")
    }

    @discardableResult
    func unequipItem(_ item: FormID?, on target: EquipmentTargetSelector) -> String {
        record("unequip \(item?.description ?? "first") on \(target)")
    }

    @discardableResult
    private func record(_ action: String) -> String {
        actions.append(action)
        return action
    }
}

/// Forwards the item seam to the shared recorder, exactly as the runtime-state
/// and trigger seams are forwarded. The conformance itself comes from
/// `WorldControlProviders`, which `FakeWorldProviders` already declares.
extension FakeWorldProviders {
    var itemControlSnapshot: ItemControlSnapshot {
        items.itemControlSnapshot
    }

    @discardableResult
    func takeInteractionTarget() -> String {
        items.takeInteractionTarget()
    }

    @discardableResult
    func openInteractionTargetContainer() -> String {
        items.openInteractionTargetContainer()
    }

    @discardableResult
    func takeAllFromOpenContainer() -> String {
        items.takeAllFromOpenContainer()
    }

    @discardableResult
    func closeOpenContainer() -> String {
        items.closeOpenContainer()
    }

    @discardableResult
    func dropPlayerItem(_ item: FormID?, count: Int32) -> String {
        items.dropPlayerItem(item, count: count)
    }

    @discardableResult
    func equipItem(_ item: FormID?, on target: EquipmentTargetSelector) -> String {
        items.equipItem(item, on: target)
    }

    @discardableResult
    func unequipItem(_ item: FormID?, on target: EquipmentTargetSelector) -> String {
        items.unequipItem(item, on: target)
    }
}

@MainActor
struct ItemsSectionTests {
    private static func stack(_ raw: UInt32, _ count: Int32, _ name: String) -> ItemStackReadout {
        ItemStackReadout(item: FormID(raw), count: count, name: name)
    }

    private static func snapshot(
        targetName: String? = "Iron Sword",
        takeable: Bool = true,
        container: Bool = false,
        playerStacks: [ItemStackReadout] = [],
        containerName: String? = nil,
        containerStacks: [ItemStackReadout] = [],
        spawned: Int = 0,
        playerEquipped: [EquippedItemReadout] = [],
        nearestActorName: String? = nil,
        nearestActorEquipped: [EquippedItemReadout] = []
    ) -> ItemControlSnapshot {
        ItemControlSnapshot(
            isAvailable: true,
            targetName: targetName,
            targetIsTakeable: takeable,
            targetIsContainer: container,
            playerStacks: playerStacks,
            playerWeight: 12.5,
            playerGold: 42,
            containerName: containerName,
            containerStacks: containerStacks,
            spawnedObjectCount: spawned,
            lastActionText: "Took 1 × Iron Sword.",
            playerEquipped: playerEquipped,
            nearestActorName: nearestActorName,
            nearestActorEquipped: nearestActorEquipped
        )
    }

    private static func worn(
        _ raw: UInt32,
        _ name: String,
        _ occupancy: String
    ) -> EquippedItemReadout {
        EquippedItemReadout(item: FormID(raw), name: name, occupancy: occupancy)
    }

    /// Loads the section's view so `makeContentViews` has run and the controls
    /// carry their identifiers.
    private static func loadedSection(
        _ provider: FakeItemProvider
    ) -> ItemsSection {
        let section = ItemsSection()
        section.provider = provider
        section.loadViewIfNeeded()
        return section
    }

    // MARK: - Accessibility contract

    @Test func controlsCarryTheirAccessibilityIdentifiers() {
        let section = Self.loadedSection(FakeItemProvider())
        #expect(section.sectionIdentifier == "items")
        #expect(section.takeControl.accessibilityIdentifier() == "ItemsTakeControl")
        #expect(section.searchControl.accessibilityIdentifier() == "ItemsSearchControl")
        #expect(section.takeAllControl.accessibilityIdentifier() == "ItemsTakeAllControl")
        #expect(
            section.closeControl.accessibilityIdentifier() == "ItemsCloseContainerControl"
        )
        #expect(section.dropControl.accessibilityIdentifier() == "ItemsDropControl")
        #expect(section.dropFormIDField.accessibilityIdentifier() == "ItemsDropFormIDField")
        #expect(section.dropCountField.accessibilityIdentifier() == "ItemsDropCountField")
        #expect(section.equipControl.accessibilityIdentifier() == "ItemsEquipControl")
        #expect(section.unequipControl.accessibilityIdentifier() == "ItemsUnequipControl")
        #expect(section.equipFormIDField.accessibilityIdentifier() == "ItemsEquipFormIDField")
        #expect(
            section.equipTargetControl.accessibilityIdentifier() == "ItemsEquipTargetControl"
        )
    }

    // MARK: - Controls reach the engine

    @Test func everyControlRunsItsEngineAction() {
        let provider = FakeItemProvider()
        let section = Self.loadedSection(provider)
        section.takeControl.performClick(nil)
        section.searchControl.performClick(nil)
        section.takeAllControl.performClick(nil)
        section.closeControl.performClick(nil)
        section.dropControl.performClick(nil)
        section.equipControl.performClick(nil)
        section.unequipControl.performClick(nil)
        #expect(provider.actions == [
            "take", "search", "takeAll", "close", "drop first×1",
            // The target picker defaults to the NPC, which is the one an equip
            // is visible on.
            "equip first on nearestActor", "unequip first on nearestActor"
        ])
    }

    /// The picker chooses the owner, and the FormID field names the item.
    @Test func equipReadsTheTargetPickerAndFormIDField() {
        let provider = FakeItemProvider()
        let section = Self.loadedSection(provider)
        section.equipTargetControl.selectedSegment = 0
        section.equipFormIDField.stringValue = "0x0001A5B0"
        section.equipControl.performClick(nil)
        section.equipTargetControl.selectedSegment = 1
        section.equipFormIDField.stringValue = ""
        section.unequipControl.performClick(nil)
        #expect(provider.actions == [
            "equip 0001A5B0 on player", "unequip first on nearestActor"
        ])
    }

    @Test func readoutStatesWhatEachOwnerIsWearing() {
        let provider = FakeItemProvider()
        let section = Self.loadedSection(provider)
        provider.itemControlSnapshot = Self.snapshot(
            playerEquipped: [Self.worn(0x300, "Iron Cuirass", "body")],
            nearestActorName: "skyrim.esm:0BAD (base 00000800)",
            nearestActorEquipped: [
                Self.worn(0x200, "Iron Sword", "right hand"),
                Self.worn(0x400, "Iron Helmet", "head")
            ]
        )
        section.refreshReadout()

        #expect(section.readout.contains("Player wears"))
        #expect(section.readout.contains("Iron Cuirass · body"))
        #expect(section.readout.contains("Nearest NPC: skyrim.esm:0BAD (base 00000800)"))
        #expect(section.readout.contains("Iron Sword · right hand"))
        #expect(section.readout.contains("Iron Helmet · head"))
    }

    @Test func readoutSaysSoWhenNothingIsWornOrNoActorIsResident() {
        let provider = FakeItemProvider()
        let section = Self.loadedSection(provider)
        provider.itemControlSnapshot = Self.snapshot()
        section.refreshReadout()

        #expect(section.readout.contains("Player wears: nothing"))
        #expect(section.readout.contains("Nearest NPC: none resident"))
    }

    /// A FormID in the field targets that item; the count field floors at one,
    /// because dropping zero or minus three of something is never what it meant.
    @Test func dropReadsTheFormIDAndCountFields() {
        let provider = FakeItemProvider()
        let section = Self.loadedSection(provider)
        section.dropFormIDField.stringValue = "0x0001A5B0"
        section.dropCountField.stringValue = "4"
        section.dropControl.performClick(nil)
        section.dropFormIDField.stringValue = "  1a5b0 "
        section.dropCountField.stringValue = "-2"
        section.dropControl.performClick(nil)
        #expect(provider.actions == ["drop 0001A5B0×4", "drop 0001A5B0×1"])
    }

    @Test func formIDParsingAcceptsBothSpellingsAndRejectsNonsense() {
        #expect(ItemsSection.parseFormID("14") == FormID(0x14))
        #expect(ItemsSection.parseFormID("0X14") == FormID(0x14))
        #expect(ItemsSection.parseFormID("") == nil)
        #expect(ItemsSection.parseFormID("not a form") == nil)
    }

    // MARK: - Readout

    @Test func readoutStatesTheTargetTheInventoryAndTheOpenContainer() {
        let provider = FakeItemProvider()
        provider.itemControlSnapshot = Self.snapshot(
            playerStacks: [Self.stack(0x200, 2, "Iron Sword")],
            containerName: "Chest",
            containerStacks: [Self.stack(0x100, 3, "Lockpick")],
            spawned: 1
        )
        let section = Self.loadedSection(provider)
        section.refreshReadout()

        #expect(section.readout.contains("Target: Iron Sword · takeable item"))
        #expect(section.readout.contains("Carried: 1 stacks · weight 12.5 · gold 42"))
        #expect(section.readout.contains("2 × Iron Sword"))
        #expect(section.readout.contains("Container: Chest"))
        #expect(section.readout.contains("3 × Lockpick"))
        #expect(section.readout.contains("Spawned objects: 1"))
        #expect(section.readout.contains("Took 1 × Iron Sword."))
    }

    @Test func readoutNamesAnEmptyInventoryAndNoOpenContainer() {
        let provider = FakeItemProvider()
        provider.itemControlSnapshot = Self.snapshot(targetName: nil, takeable: false)
        let section = Self.loadedSection(provider)
        section.refreshReadout()
        #expect(section.readout.contains("Target: none"))
        #expect(section.readout.contains("Carried: empty"))
        #expect(section.readout.contains("Container: none open"))
    }

    /// A long inventory is truncated with a stated remainder, so the readout
    /// never shows part of one as the whole of it.
    @Test func readoutStatesWhatItTruncated() {
        let provider = FakeItemProvider()
        provider.itemControlSnapshot = Self.snapshot(
            playerStacks: (0 ..< 12).map { Self.stack(UInt32($0), 1, "Item\($0)") }
        )
        let section = Self.loadedSection(provider)
        section.refreshReadout()
        #expect(section.readout.contains("… 4 more"))
    }

    /// No game data means no inventory runtime, which the panel says rather
    /// than showing a convincing empty inventory.
    @Test func readoutReportsAnUnavailableRuntime() {
        let section = Self.loadedSection(FakeItemProvider())
        section.refreshReadout()
        #expect(section.readout == ItemControlSnapshot.unavailable.lastActionText)
    }
}
