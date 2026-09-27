// M19 milestone panel acceptance (issue #475, roadmap item 19.12): one
// uninterrupted run through the real sidebar model and the registry-built
// World > Combat & Physics panel on a single provider set, in the M10-M18
// acceptance-triad shape, plus the two surfaces the milestone's magic also
// prints on — the enchanted-equipment readout and the Asset Browser's magic
// record families.
//
// The readouts are found by their accessibility identifiers, which is the
// deterministic substitute while UI automation is TCC-blocked
// (docs/tools/environment.md). What this adds over the section suites is that
// the whole surface works as one, in the order a magic session uses it: read
// what the actor is worth and what resists what, learn a spell, ready it to a
// hand, cast it, read what the projectile did to whom, and read what the
// enchanted weapon has left — without a single fake being swapped halfway.

import AppKit
@testable import opensky
import Testing

@MainActor
struct M19AcceptancePanelTests {
    @Test
    func theCombatDestinationRunsTheWholeMagicAcceptanceFlow() throws {
        let providers = FakeWorldProviders()
        providers.actorValues.snapshot = M19Fixture.actorValues
        providers.magicEffects.snapshot = M19Fixture.magicEffects
        providers.casting.snapshot = M19Fixture.casting
        providers.combatLoop.snapshot = M19Fixture.combatLoop

        let panel = try Self.buildPanel(providers: providers)
        panel.startInspecting()
        defer { panel.stopInspecting() }

        Self.expectEveryReadout(panel)
        Self.castTheSpell(panel, providers: providers)
        Self.readTheResistance(panel, providers: providers)
        Self.switchOffNPCCasting(panel, providers: providers)
    }

    /// The sidebar row and the registry factory, taken through the same path
    /// the app takes rather than by constructing the panel directly.
    private static func buildPanel(
        providers: FakeWorldProviders
    ) throws -> CombatPhysicsPanelViewController {
        let worldGroup = try #require(
            AppSidebarModel.groups().first { $0.section == .world }
        )
        let descriptor = try #require(
            worldGroup.destinations.first { $0.id == "combatPhysics" }
        )
        #expect(descriptor.sidebarIdentifier == "Destination-combatPhysics")
        #expect(descriptor.title == "Combat & Physics")

        guard case let .worldInspector(makePanel) = descriptor.content else {
            Issue.record("World > Combat & Physics is not a world inspector")
            throw M19PanelAcceptanceError.notAWorldInspector
        }
        let panel = try #require(
            makePanel(WorldPanelContext(providers: providers))
                as? CombatPhysicsPanelViewController
        )
        panel.loadViewIfNeeded()
        return panel
    }

    /// The four magic sections sit in the order a cast is read in — what the
    /// bodies are worth, what is running on them, what is being cast, and
    /// whether the fighters are casting too — and each publishes its section id.
    @Test
    func theMagicSectionsAreOrderedAndIdentified() throws {
        let panel = try Self.buildPanel(providers: FakeWorldProviders())
        let identifiers = panel.makeSections().map(\.sectionIdentifier)
        let magic = identifiers.filter {
            ["combatActorValues", "combatMagicEffects", "combatSpellcasting", "combatLoop"]
                .contains($0)
        }
        #expect(magic == [
            "combatActorValues", "combatMagicEffects", "combatSpellcasting", "combatLoop"
        ])
        #expect(identifiers.firstIndex(of: "combatMagicEffects")
            == identifiers.firstIndex(of: "combatActorValues").map { $0 + 1 })
    }

    /// Every readout the milestone's surface publishes, read back by
    /// accessibility id. A session mid-cast has to be legible in all four.
    private static func expectEveryReadout(_ panel: CombatPhysicsPanelViewController) {
        let view = panel.view
        // 19.5 — the selected actor value, its modifier slots, and the capped
        // fraction of damage a percentage resistance removes.
        #expect(scriptsReadout("CombatActorValuesStatsLabel", in: view)?
            .contains("Selected value: Resist Fire (41)") == true)
        #expect(scriptsReadout("CombatActorValuesStatsLabel", in: view)?
            .contains("resists 40% (capped)") == true)
        // 19.6 — what is running on the player and on the actor the resistance
        // above belongs to.
        #expect(scriptsReadout("CombatMagicEffectsStatsLabel", in: view)?
            .contains("Player effects (1):") == true)
        #expect(scriptsReadout("CombatMagicEffectsStatsLabel", in: view)?
            .contains("Nearest actor effects — Bandit (1):") == true)
        #expect(scriptsReadout("CombatMagicEffectsStatsLabel", in: view)?
            .contains("Firebolt (spell) damages Health") == true)
        // 19.7 — the spellbook, the hands and the magicka that pays for them.
        #expect(scriptsReadout("CombatSpellcastingStatsLabel", in: view)?
            .contains("Known spells (2):") == true)
        #expect(scriptsReadout("CombatSpellcastingStatsLabel", in: view)?
            .contains("readied in right hand") == true)
        #expect(scriptsReadout("CombatSpellcastingStatsLabel", in: view)?
            .contains("magicka 59 / 100") == true)
        // 19.8 — what left the caster and what the resistance did to it.
        #expect(scriptsReadout("CombatSpellcastingStatsLabel", in: view)?
            .contains("Delivery: 1 projectile(s)") == true)
        #expect(scriptsReadout("CombatSpellcastingStatsLabel", in: view)?
            .contains("FireDamageFFAimed on Bandit: 25.0 x 0.600 = 15.0") == true)
        // 19.11 — the magic condition functions answering about the player.
        #expect(scriptsReadout("CombatSpellcastingStatsLabel", in: view)?
            .contains("HasSpell(Firebolt) -> 1") == true)
        // 19.10 — what the fighting NPCs did with the spells they know.
        #expect(scriptsReadout("CombatLoopStatsLabel", in: view)?
            .contains("AI casting: on — 1 of 1 fighters armed, 2 spells cast") == true)
    }

    /// Step 1 — the cast itself. Learn, select, ready and cast all reach the
    /// engine entry points item 19.7 specified, with the hand each names.
    private static func castTheSpell(
        _ panel: CombatPhysicsPanelViewController,
        providers: FakeWorldProviders
    ) {
        sendScriptsControl(panel.spellcastingLearnControl)
        sendScriptsControl(panel.spellcastingSection.selectControl)
        sendScriptsControl(panel.spellcastingSection.readyRightControl)
        sendScriptsControl(panel.spellcastingCastRightControl)

        #expect(providers.casting.learnCount == 1)
        #expect(providers.casting.selectCount == 1)
        #expect(providers.casting.readied == [.right])
        #expect(providers.casting.cast == [.right])
    }

    /// Step 2 — the resistance the hit was scaled by, asked for by name in the
    /// same section that reports the bars it moved (item 19.5).
    private static func readTheResistance(
        _ panel: CombatPhysicsPanelViewController,
        providers: FakeWorldProviders
    ) {
        let section = panel.actorValuesSection
        let index = CombatActorValuesSection.targets.firstIndex(of: .nearestActor) ?? 0
        section.targetControl.selectItem(at: index)
        sendScriptsControl(section.targetControl)
        #expect(providers.actorValues.target == .nearestActor)

        section.valueNameControl.stringValue = "Resist Fire"
        sendScriptsControl(section.damageControl)
        #expect(providers.actorValues.selection == 41)
    }

    /// Step 3 — the one switch item 19.10 added: turning NPC casting off is how
    /// "the decision layer chose a swing" is told apart from "nothing it knows
    /// is deliverable".
    private static func switchOffNPCCasting(
        _ panel: CombatPhysicsPanelViewController,
        providers: FakeWorldProviders
    ) {
        #expect(providers.combatLoop.allowsCasting)
        panel.actorCastingControl.state = .off
        sendScriptsControl(panel.actorCastingControl)
        #expect(!providers.combatLoop.allowsCasting)
    }

    // MARK: - Enchanted equipment (item 19.9)

    /// A charge is a fact about an equipped item, so it prints where equipped
    /// items already print rather than under a magic destination of its own.
    @Test
    func theEnchantedWeaponsChargeIsReadableWhereEquippedItemsPrint() throws {
        let providers = FakeWorldProviders()
        let descriptor = try #require(DestinationRegistry.destination(id: "inventoryEquipment"))
        #expect(descriptor.sidebarIdentifier == "Destination-inventoryEquipment")
        guard case let .worldInspector(makePanel) = descriptor.content else {
            Issue.record("World > Inventory & Equipment is not a world inspector")
            throw M19PanelAcceptanceError.notAWorldInspector
        }
        let panel = try #require(
            makePanel(WorldPanelContext(providers: providers))
                as? InventoryEquipmentPanelViewController
        )
        panel.loadViewIfNeeded()
        panel.startInspecting()
        defer { panel.stopInspecting() }

        let section = panel.equipmentSection
        section.targetControl.selectedSegment = 1
        sendScriptsControl(section.targetControl)
        #expect(section.inspectionTarget == .nearestActor)

        let readout = try #require(
            scriptsReadout("EquipmentInspectionStatsLabel", in: panel.view)
        )
        #expect(readout.contains("IronSword · right hand"))
        #expect(readout.contains("Fire Damage (on hit) · 2926/3000 charge, 79 use(s) left"))
    }

    // MARK: - Asset Browser (scope point 1)

    /// The nine magic record families are browsable by editor id from the
    /// load-order record surface M18 built, which is what makes a spell's
    /// effect table and a shout's words reachable without a CLI command.
    @Test
    func theAssetBrowserBrowsesEveryMagicRecordFamily() throws {
        let magicTypes: [ReferenceRecordType] = [
            .magicEffect, .spell, .scroll, .enchantment, .shout,
            .wordOfPower, .leveledSpell, .dualCastData, .equipSlot
        ]
        #expect(magicTypes.map(\.fourCC) == [
            "MGEF", "SPEL", "SCRL", "ENCH", "SHOU", "WOOP", "LVSP", "DUAL", "EQUP"
        ])

        let panel = PreviewViewController()
        panel.startupErrorMessage = "test"
        panel.loadViewIfNeeded()
        let recordIndex = try #require(
            PreviewCategory.allCases.firstIndex(of: .referenceRecords)
        )
        panel.categoryPopUp.selectItem(at: recordIndex)
        panel.categoryChanged()

        let titles = panel.recordTypePopUp.itemTitles
        for type in magicTypes {
            #expect(titles.contains(type.title), "\(type.fourCC) is not browsable")
        }
        #expect(panel.recordTypePopUp.accessibilityIdentifier() == "AssetRecordTypeControl")
        #expect(panel.tableView.accessibilityIdentifier() == "AssetTable")
    }
}

/// Thrown only to end the run early when the registry hands back something
/// other than a world inspector, which `Issue.record` has already reported.
private enum M19PanelAcceptanceError: Error {
    case notAWorldInspector
}
