// World > Inventory & Equipment acceptance-surface coverage (issue #180).
// Synthetic provider state only; the engine-side loop proof is
// `M12AcceptanceTests` and the pixel evidence is `M12AcceptanceRenderTests`.

import AppKit
@testable import opensky
import Testing

@MainActor
private func tap(_ control: NSControl) {
    control.sendAction(control.action, to: control.target)
}

struct InventoryEquipmentPanelTests {
    @MainActor
    private func makePanel(
        _ provider: FakeWorldProviders
    ) -> InventoryEquipmentPanelViewController {
        let panel = InventoryEquipmentPanelViewController()
        panel.provider = provider
        panel.loadViewIfNeeded()
        return panel
    }

    /// Accessibility ids are the UI-test contract; pin them literally, and
    /// change these literals in the same commit that renames one.
    @Test @MainActor
    func sectionsExposeStableIdentifiers() {
        let panel = makePanel(FakeWorldProviders())
        #expect(panel.grantsSection.sectionIdentifier == "inventoryGrants")
        #expect(panel.ownershipSection.sectionIdentifier == "itemOwnership")
        #expect(panel.equipmentSection.sectionIdentifier == "equipmentInspection")
        let controls: [(NSView, String)] = [
            (panel.grantsSection.formIDField, "InventoryGrantFormIDField"),
            (panel.grantsSection.countField, "InventoryGrantCountField"),
            (panel.grantsSection.targetControl, "InventoryGrantTargetControl"),
            (panel.grantsSection.grantControl, "InventoryGrantControl"),
            (panel.equipmentSection.targetControl, "EquipmentInspectionTargetControl")
        ]
        for (control, identifier) in controls {
            #expect(control.accessibilityIdentifier() == identifier)
        }
    }

    /// The three sections appear in the order the gate's loop reaches for them,
    /// and each has a header title a record can name.
    @Test @MainActor
    func sectionOrderAndTitlesArePinned() {
        let panel = makePanel(FakeWorldProviders())
        let sections = panel.makeSections()
        #expect(sections.map(\.sectionIdentifier) == [
            "inventoryGrants", "itemOwnership", "equipmentInspection"
        ])
        #expect(sections.map(\.sectionTitle) == ["Grants", "Ownership", "Equipment"])
    }

    @Test @MainActor
    func grantDrivesTheProviderAndShowsTheResult() {
        let provider = FakeWorldProviders()
        let panel = makePanel(provider)
        let section = panel.grantsSection

        section.formIDField.stringValue = "200"
        section.countField.stringValue = "3"
        tap(section.grantControl)

        #expect(provider.inventoryEquipment.playerCount == 4)
        #expect(section.readout.contains("Granted 3 × IronSword to Player."))
        #expect(section.readout.contains("4 × IronSword"))
    }

    /// A blank or unparseable FormID must refuse in place rather than reach the
    /// provider, because there is no "first stack" default that a grant could
    /// sensibly mean.
    @Test @MainActor
    func grantWithoutAFormIDRefusesWithoutCallingTheProvider() {
        let provider = FakeWorldProviders()
        let panel = makePanel(provider)
        let section = panel.grantsSection

        section.formIDField.stringValue = "  "
        tap(section.grantControl)
        #expect(provider.inventoryEquipment.playerCount == 1)
        #expect(section.readout == "Grant refused: type the item's FormID in hexadecimal.")

        section.formIDField.stringValue = "not-hex"
        tap(section.grantControl)
        #expect(provider.inventoryEquipment.playerCount == 1)
    }

    /// The count field is floored at one: a grant of zero or minus three is
    /// never what the field meant.
    @Test @MainActor
    func grantCountIsFlooredAtOne() {
        let provider = FakeWorldProviders()
        let panel = makePanel(provider)
        let section = panel.grantsSection
        section.formIDField.stringValue = "0x200"

        section.countField.stringValue = "0"
        tap(section.grantControl)
        #expect(provider.inventoryEquipment.playerCount == 2)

        section.countField.stringValue = "-3"
        tap(section.grantControl)
        #expect(provider.inventoryEquipment.playerCount == 3)
    }

    /// Granting into a container the session has not opened is a stated refusal
    /// rather than a silent no-op.
    @Test @MainActor
    func grantIntoAClosedContainerIsRefused() {
        let provider = FakeWorldProviders()
        let panel = makePanel(provider)
        let section = panel.grantsSection
        section.formIDField.stringValue = "200"
        section.targetControl.selectedSegment = 1
        #expect(section.grantTarget == .openContainer)

        tap(section.grantControl)
        #expect(provider.inventoryEquipment.containerCount == 0)
        #expect(section.readout.contains("Grant refused: no container is open."))

        provider.inventoryEquipment.containerIsOpen = true
        tap(section.grantControl)
        section.refreshReadout()
        #expect(provider.inventoryEquipment.containerCount == 1)
        #expect(section.readout.contains("Container: Test Chest · gold 500"))
    }

    /// The ownership readout names the theft answer for both an unowned and an
    /// owned reference, and says that nothing enforces it.
    @Test @MainActor
    func ownershipReadoutStatesTheTheftAnswer() {
        let provider = FakeWorldProviders()
        let panel = makePanel(provider)
        let section = panel.ownershipSection

        section.refreshReadout()
        #expect(section.readout.contains("Owner: none — taking this is not theft."))

        provider.inventoryEquipment.ownership = ReferenceOwnershipReadout(
            name: "Chest", reference: FormID(0x0710), owner: FormID(0x3000), factionRank: 2
        )
        section.refreshReadout()
        #expect(section.readout.contains("taking this is theft."))
        #expect(section.readout.contains("Faction rank required: 2"))
        #expect(section.readout.contains("no crime system enforces it yet"))

        provider.inventoryEquipment.ownership = nil
        section.refreshReadout()
        #expect(section.readout.contains("Target: none"))
    }

    /// The owner selector drives the provider, and the readout follows it —
    /// including the appearance skips, which are the reason the section exists.
    @Test @MainActor
    func equipmentSelectorSwitchesOwnerAndShowsAppearanceSkips() {
        let provider = FakeWorldProviders()
        let panel = makePanel(provider)
        let section = panel.equipmentSection

        section.refreshReadout()
        #expect(section.inspectionTarget == .nearestActor)
        #expect(section.readout.contains("Inspecting: Nearest NPC"))
        #expect(section.readout.contains("Appearance source: runtime equipped set"))
        #expect(section.readout.contains("IronSword · right hand"))
        #expect(section.readout.contains("maskedByOutfit (00000300)"))

        section.targetControl.selectedSegment = 0
        tap(section.targetControl)
        section.refreshReadout()
        #expect(provider.inventoryEquipmentInspectionTarget == .player)
        #expect(section.readout.contains("Inspecting: Player · the player"))
        #expect(section.readout.contains("Wearing: nothing"))
        #expect(section.readout.contains("Appearance skips: none"))
    }

    /// Inspecting the player is this destination's one departure from a
    /// documented default, so it lights the section and the sidebar dot, and
    /// the reset puts it back.
    @Test @MainActor
    func inspectingThePlayerIsTheOnlyOverride() {
        let provider = FakeWorldProviders()
        let panel = makePanel(provider)
        let section = panel.equipmentSection
        #expect(!section.isOverridden)

        provider.inventoryEquipmentInspectionTarget = .player
        #expect(section.isOverridden)

        section.performResetToDefaults()
        #expect(provider.inventoryEquipmentInspectionTarget == .nearestActor)
        #expect(!section.isOverridden)
        #expect(section.targetControl.selectedSegment == 1)
    }

    /// No game data means every section says so rather than showing a
    /// convincing empty inventory.
    @Test @MainActor
    func unavailableRuntimeIsStatedInEverySection() {
        let provider = FakeWorldProviders()
        provider.inventoryEquipment.isAvailable = false
        let panel = makePanel(provider)
        let expected = InventoryEquipmentSnapshot.unavailable.lastActionText

        for section in [panel.grantsSection, panel.ownershipSection, panel.equipmentSection] {
            section.refreshReadout()
        }
        #expect(panel.grantsSection.readout == expected)
        #expect(panel.ownershipSection.readout == expected)
        #expect(panel.equipmentSection.readout == expected)
    }

    /// Layout invariant: no section control pins a hard height, which would
    /// defeat intrinsic sizing and survive collapsing the section.
    @Test @MainActor
    func noSectionControlPinsAHardHeight() {
        let panel = makePanel(FakeWorldProviders())
        for section in panel.makeSections() {
            section.loadViewIfNeeded()
            for view in section.view.subviews {
                #expect(!view.constraints.contains { $0.firstAttribute == .height })
            }
        }
    }
}
