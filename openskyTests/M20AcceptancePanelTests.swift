// M20 milestone panel acceptance (issue #500, roadmap item 20.7): one
// uninterrupted run through the real sidebar model and the registry-built
// `World > Progression` panel on one wired session, in the M10-M19
// acceptance-triad shape, plus the Asset Browser families the milestone's two
// new record types are browsable from.
//
// The readouts are found by their accessibility identifiers, which is the
// deterministic substitute while UI automation is TCC-blocked
// (docs/tools/environment.md). What this adds over the section suite is that
// the whole surface works as one, in the order progression happens in: read
// what the character is, use a skill until it levels, spend the character
// experience that banked, take the attribute the level owes, buy a perk with
// the point it granted, and read the record that perk resolves to — with no
// fake standing in for a runtime anywhere.

import AppKit
@testable import opensky
import Testing

@MainActor
struct M20AcceptancePanelTests {
    @Test
    func theProgressionDestinationRunsTheWholeAcceptanceFlow() throws {
        let controller = try M20Fixture.controller()
        let panel = try Self.buildPanel(providers: controller)
        panel.startInspecting()
        defer { panel.stopInspecting() }

        Self.readTheFreshCharacter(panel)
        Self.useTheSkillUntilItLevels(panel, controller: controller)
        Self.takeTheLevelAndItsAttribute(panel, controller: controller)
        Self.buyThePerkWithThePoint(panel, controller: controller)
        Self.grantAndRemoveWithoutTheRules(panel, controller: controller)
    }

    /// The sidebar row and the registry factory, taken through the same path
    /// the app takes rather than by constructing the panel directly.
    private static func buildPanel(
        providers: GameViewController
    ) throws -> ProgressionPanelViewController {
        let worldGroup = try #require(
            AppSidebarModel.groups().first { $0.section == .world }
        )
        let descriptor = try #require(
            worldGroup.destinations.first { $0.id == "progression" }
        )
        #expect(descriptor.sidebarIdentifier == "Destination-progression")
        #expect(descriptor.title == "Progression")

        guard case let .worldInspector(makePanel) = descriptor.content else {
            Issue.record("World > Progression is not a world inspector")
            throw ProgressionPanelError.notAWorldInspector
        }
        let panel = try #require(
            makePanel(WorldPanelContext(providers: providers))
                as? ProgressionPanelViewController
        )
        panel.loadViewIfNeeded()
        return panel
    }

    /// Scope point 2: level, experience, perk points and the eighteen skills
    /// are all readable before anything is done to them.
    private static func readTheFreshCharacter(_ panel: ProgressionPanelViewController) {
        let character = readout("ProgressionCharacterStatsLabel", in: panel)
        #expect(character.contains("level 1"))
        #expect(character.contains("0 perk point(s)"))
        #expect(character.contains("0 attribute pick(s) owed"))

        let skills = readout("ProgressionSkillsStatsLabel", in: panel)
        #expect(skills.contains("Skills (18):"))
        #expect(skills.contains("> One-Handed"))
        // The fixture load order carries one AVIF record; the other seventeen
        // skills still list, named from the vanilla actor-value table.
        #expect(skills.contains("Destruction"))
    }

    /// Scope point 3: granting use drives `SkillAdvancementRuntime.advance`,
    /// which is the same call a swing makes, and the skill and its banked
    /// experience both move.
    private static func useTheSkillUntilItLevels(
        _ panel: ProgressionPanelViewController,
        controller: GameViewController
    ) {
        let before = controller.progressionControlSnapshot
        let skillBefore = before.selectedSkillReadout?.base ?? 0

        panel.skillsSection.amountControl.stringValue = "400"
        sendScriptsControl(panel.advanceSkillControl)

        let after = controller.progressionControlSnapshot
        let skillAfter = after.selectedSkillReadout?.base ?? 0
        #expect(skillAfter > skillBefore, "400 uses did not move One-handed")
        #expect(after.skillIncreases > 0)
        #expect(after.experience > 0 || after.level > before.level)

        panel.skillsSection.refreshReadout()
        panel.characterSection.refreshReadout()
        #expect(readout("ProgressionCharacterStatsLabel", in: panel).contains("One-Handed"))
    }

    /// Scope point 3: awarding character experience crosses the level curve,
    /// and the pick the level owes is spent through
    /// `PlayerLevelRuntime.chooseAttribute` — the same call a level-up screen
    /// would make.
    private static func takeTheLevelAndItsAttribute(
        _ panel: ProgressionPanelViewController,
        controller: GameViewController
    ) {
        panel.characterSection.experienceControl.stringValue = "5000"
        sendScriptsControl(panel.awardExperienceControl)

        let leveled = controller.progressionControlSnapshot
        #expect(leveled.level > 1, "5000 character XP bought no level")
        #expect(leveled.perkPoints > 0)
        #expect(leveled.pendingAttributePicks > 0)

        let healthBefore = controller.actorValues.runtime?
            .baseValue(at: ActorValueIdentity.index(of: .health), on: .player) ?? 0
        // Health is the popup's first row, which is where it starts.
        sendScriptsControl(panel.chooseAttributeControl)
        let picked = controller.progressionControlSnapshot
        #expect(picked.pendingAttributePicks == leveled.pendingAttributePicks - 1)
        #expect(picked.attributePicks.last == .health)
        let healthAfter = controller.actorValues.runtime?
            .baseValue(at: ActorValueIdentity.index(of: .health), on: .player) ?? 0
        #expect(healthAfter > healthBefore, "the pick added no health")

        panel.characterSection.refreshReadout()
        let character = readout("ProgressionCharacterStatsLabel", in: panel)
        #expect(character.contains("HP 1"))
    }

    /// Scope points 3 and 4: the tree lists its boxes with their connections,
    /// and Spend point takes the real path — tree, rank order and the record's
    /// own conditions — before the point leaves the pool.
    private static func buyThePerkWithThePoint(
        _ panel: ProgressionPanelViewController,
        controller: GameViewController
    ) {
        controller.progressionNodeSelection = M20Fixture.damageNode
        panel.perkTreeSection.refreshReadout()

        let tree = readout("ProgressionPerkTreeStatsLabel", in: panel)
        #expect(tree.contains("Perk tree: One-Handed (4 nodes):"))
        #expect(tree.contains("#0 (tree entry)"))
        #expect(tree.contains("#1 Damage Rank 1"))
        #expect(tree.contains("lines to [2, 3]"))
        #expect(tree.contains("available"))

        // Scope point 4: the selected box resolves to its PERK record, with the
        // entry point its effect hooks.
        let perk = readout("ProgressionPerkStatsLabel", in: panel)
        #expect(perk.contains("Damage Rank 1 [DamageRank1]"))
        #expect(perk.contains("Mod Attack Damage"))
        #expect(perk.contains("not owned"))

        let before = controller.progressionControlSnapshot
        let points = before.perkPoints
        #expect(before.selectedSkillReadout?.ownedPerks == 0)
        sendScriptsControl(panel.spendPerkPointControl)
        let spent = controller.progressionControlSnapshot
        #expect(spent.perkPoints == points - 1)
        #expect(spent.ownedPerkCount == 1)
        #expect(spent.selectedNodeReadout?.isOwned == true)
        // The skill line's perk count is cached per skill (issue #556), so the
        // spend has to move it rather than leave the reading it was taken from
        // standing.
        #expect(spent.selectedSkillReadout?.ownedPerks == 1)

        panel.perkTreeSection.refreshReadout()
        panel.characterSection.refreshReadout()
        #expect(readout("ProgressionPerkStatsLabel", in: panel).contains("— owned"))
        #expect(
            readout("ProgressionCharacterStatsLabel", in: panel)
                .contains("Spent a point on Damage Rank 1")
        )
    }

    /// Scope point 3: Grant and Remove are the way around the rules, for
    /// reading what a perk does without qualifying for it, and both go through
    /// the ownership runtime rather than a panel-side set.
    private static func grantAndRemoveWithoutTheRules(
        _ panel: ProgressionPanelViewController,
        controller: GameViewController
    ) {
        controller.progressionNodeSelection = M20Fixture.blockingNode
        sendScriptsControl(panel.grantPerkControl)
        #expect(controller.progressionControlSnapshot.ownedPerkCount == 2)
        #expect(controller.progressionControlSnapshot.perk?.isOwned == true)

        sendScriptsControl(panel.removePerkControl)
        #expect(controller.progressionControlSnapshot.ownedPerkCount == 1)
        panel.perkTreeSection.refreshReadout()
        #expect(readout("ProgressionPerkStatsLabel", in: panel).contains("Shield Wall"))
    }

    /// Scope point 5: both M20 record types are browsable by editor id from the
    /// load-order record surface, which is what makes an AVIF perk grid and a
    /// PERK effect table reachable without a CLI command.
    @Test
    func theAssetBrowserBrowsesBothProgressionRecordTypes() throws {
        let types: [ReferenceRecordType] = [.actorValueInformation, .perk]
        #expect(types.map(\.fourCC) == ["AVIF", "PERK"])

        let panel = PreviewViewController()
        panel.startupErrorMessage = "test"
        panel.loadViewIfNeeded()
        let recordIndex = try #require(
            PreviewCategory.allCases.firstIndex(of: .referenceRecords)
        )
        panel.categoryPopUp.selectItem(at: recordIndex)
        panel.categoryChanged()

        let titles = panel.recordTypePopUp.itemTitles
        for type in types {
            #expect(titles.contains(type.title), "\(type.fourCC) is not browsable")
        }
        #expect(panel.recordTypePopUp.accessibilityIdentifier() == "AssetRecordTypeControl")
        #expect(panel.tableView.accessibilityIdentifier() == "AssetTable")
    }

    private static func readout(
        _ identifier: String,
        in panel: ProgressionPanelViewController
    ) -> String {
        scriptsReadout(identifier, in: panel.view) ?? ""
    }
}
