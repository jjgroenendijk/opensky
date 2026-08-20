// The World > Progression panel (issue #500, roadmap item 20.7): its geometry,
// its accessibility-id contract, and that each control sends what its field and
// popup hold rather than a default it invented.
//
// The panel is built through the registry factory the app itself uses, so what
// is under test is the destination a user clicks rather than a hand-assembled
// copy of it.

import AppKit
@testable import opensky
import Testing

@MainActor
struct ProgressionPanelTests {
    /// The registry factory, taken through the same path the shell takes.
    static func panel(
        providers: FakeWorldProviders
    ) throws -> ProgressionPanelViewController {
        let descriptor = try #require(DestinationRegistry.destination(id: "progression"))
        #expect(descriptor.sidebarIdentifier == "Destination-progression")
        #expect(descriptor.title == "Progression")
        #expect(descriptor.section == .world)
        guard case let .worldInspector(makePanel) = descriptor.content else {
            throw ProgressionPanelError.notAWorldInspector
        }
        let panel = try #require(
            makePanel(WorldPanelContext(providers: providers))
                as? ProgressionPanelViewController
        )
        panel.loadViewIfNeeded()
        return panel
    }

    /// A snapshot with a character, three skills and a two-box tree — enough
    /// for every readout to have something to say.
    static func snapshot() -> ProgressionControlSnapshot {
        makeProgressionSnapshot(
            level: 4,
            experience: 120,
            experienceForNextLevel: 400,
            perkPoints: 2,
            pendingAttributePicks: 1,
            attributePicks: [.health, .stamina],
            skillIncreases: 6,
            ownedPerkCount: 1,
            skills: [
                makeSkillReadout(name: "One-handed", index: 6, current: 22, base: 20),
                makeSkillReadout(name: "Two-handed", index: 7),
                makeSkillReadout(name: "Destruction", index: 21, treePerks: 4)
            ],
            selectedSkill: 6,
            treeNodes: [
                makePerkTreeNode(
                    node: 0, name: "(tree entry)", grantsNoPerk: true,
                    requiresParent: false, connections: [7]
                ),
                makePerkTreeNode(
                    node: 7, name: "Armsman", isOwned: true, connections: [1],
                    ownedRank: 1, rankCount: 5, refusal: .alreadyOwned
                )
            ],
            selectedNode: 7,
            perk: PerkInspection(
                name: "Armsman",
                editorID: "Armsman00",
                formID: "Skyrim.esm:000BABE4",
                isPlayable: true,
                isTrait: false,
                isHidden: false,
                isOwned: true,
                conditions: ["GetBaseActorValue OneHanded >= 0.0"],
                effects: ["entry point rank 1: Mod Attack Damage (35), multiply value"]
            ),
            lastActionText: "Granted Armsman."
        )
    }

    /// The destination sits at the end of the simulation destinations, after
    /// Dialogue & Voice and before the menus, and carries its own SF Symbol.
    @Test
    func descriptorPlacementIsPinned() throws {
        let descriptor = try #require(DestinationRegistry.destination(id: "progression"))
        #expect(descriptor.symbolName == "chart.line.uptrend.xyaxis")
        #expect(descriptor.showsGameView)
        #expect(descriptor.isWorldInspector)
        // No override actions: nothing under this destination is a setting.
        #expect(descriptor.overrides == nil)

        let ids = DestinationRegistry.all.map(\.id)
        let index = try #require(ids.firstIndex(of: "progression"))
        #expect(ids[index - 1] == "dialogueVoice")
        #expect(ids[index + 1] == "systemMenu")
    }

    @Test
    func theSectionsCarryTheirHeaderIdentifiers() throws {
        let panel = try Self.panel(providers: FakeWorldProviders())
        #expect(panel.characterSection.sectionIdentifier == "progressionCharacter")
        #expect(panel.skillsSection.sectionIdentifier == "progressionSkills")
        #expect(panel.perkTreeSection.sectionIdentifier == "progressionPerkTree")
        #expect(panel.characterSection.sectionTitle == "Character")
        #expect(panel.skillsSection.sectionTitle == "Skills")
        #expect(panel.perkTreeSection.sectionTitle == "Perk Tree")
    }

    /// Every control id is the UI-test API; pin them literally here so a rename
    /// cannot land without updating the contract.
    @Test
    func theControlIdentifiersAreTheDocumentedOnes() throws {
        let panel = try Self.panel(providers: FakeWorldProviders())
        let character = panel.characterSection
        #expect(
            character.experienceControl.accessibilityIdentifier()
                == "ProgressionExperienceControl"
        )
        #expect(
            character.awardExperienceControl.accessibilityIdentifier()
                == "ProgressionAwardExperienceControl"
        )
        #expect(
            character.attributeControl.accessibilityIdentifier()
                == "ProgressionAttributeControl"
        )
        #expect(
            character.chooseAttributeControl.accessibilityIdentifier()
                == "ProgressionChooseAttributeControl"
        )
        #expect(
            character.addPerkPointControl.accessibilityIdentifier()
                == "ProgressionAddPerkPointControl"
        )
        #expect(
            character.removePerkPointControl.accessibilityIdentifier()
                == "ProgressionRemovePerkPointControl"
        )
        let skills = panel.skillsSection
        #expect(skills.skillControl.accessibilityIdentifier() == "ProgressionSkillControl")
        #expect(
            skills.amountControl.accessibilityIdentifier() == "ProgressionSkillAmountControl"
        )
        #expect(
            skills.advanceControl.accessibilityIdentifier()
                == "ProgressionAdvanceSkillControl"
        )
        #expect(
            skills.incrementControl.accessibilityIdentifier()
                == "ProgressionIncrementSkillControl"
        )
        let tree = panel.perkTreeSection
        #expect(tree.skillControl.accessibilityIdentifier() == "ProgressionTreeSkillControl")
        #expect(tree.nodeControl.accessibilityIdentifier() == "ProgressionPerkNodeControl")
        #expect(
            tree.spendControl.accessibilityIdentifier() == "ProgressionSpendPerkPointControl"
        )
        #expect(tree.grantControl.accessibilityIdentifier() == "ProgressionGrantPerkControl")
        #expect(
            tree.removeControl.accessibilityIdentifier() == "ProgressionRemovePerkControl"
        )
    }

    /// Every readout label is reachable by its identifier in the built view
    /// hierarchy and carries the snapshot's numbers.
    @Test
    func theReadoutsCarryTheSnapshot() throws {
        let providers = FakeWorldProviders()
        providers.progression.snapshot = Self.snapshot()
        let panel = try Self.panel(providers: providers)
        panel.startInspecting()
        defer { panel.stopInspecting() }

        let character = try #require(
            scriptsReadout("ProgressionCharacterStatsLabel", in: panel.view)
        )
        #expect(character.contains("level 4 — 120/400 XP  2 perk point(s)"))
        #expect(character.contains("1 attribute pick(s) owed"))
        #expect(character.contains("HP 1  MP 0  SP 1"))
        #expect(character.contains("Granted Armsman."))

        let skills = try #require(
            scriptsReadout("ProgressionSkillsStatsLabel", in: panel.view)
        )
        #expect(skills.contains("Skills (3):"))
        #expect(skills.contains("> One-handed"))
        #expect(skills.contains("Destruction"))

        let tree = try #require(
            scriptsReadout("ProgressionPerkTreeStatsLabel", in: panel.view)
        )
        #expect(tree.contains("Perk tree: One-handed (2 nodes):"))
        #expect(tree.contains("#7 Armsman (rank 1/5) — owned"))
        #expect(tree.contains("lines to [1]"))

        let perk = try #require(scriptsReadout("ProgressionPerkStatsLabel", in: panel.view))
        #expect(perk.contains("Armsman [Armsman00] Skyrim.esm:000BABE4 — owned"))
        #expect(perk.contains("GetBaseActorValue OneHanded"))
        #expect(perk.contains("Mod Attack Damage (35)"))
    }

    /// With no runtime attached, every readout says so rather than showing a
    /// convincing zero.
    @Test
    func withNoRuntimeThePanelSaysSo() throws {
        let providers = FakeWorldProviders()
        let panel = try Self.panel(providers: providers)
        panel.startInspecting()
        defer { panel.stopInspecting() }

        let character = try #require(
            scriptsReadout("ProgressionCharacterStatsLabel", in: panel.view)
        )
        #expect(character.contains("Character: unavailable"))
        let skills = try #require(
            scriptsReadout("ProgressionSkillsStatsLabel", in: panel.view)
        )
        #expect(skills.contains("Skills: unavailable"))
        let tree = try #require(
            scriptsReadout("ProgressionPerkTreeStatsLabel", in: panel.view)
        )
        #expect(tree.contains("Perk tree: unavailable"))
    }

    /// Every control sends what its field and popup hold.
    @Test
    func theControlsSendWhatTheFieldsHold() throws {
        let providers = FakeWorldProviders()
        providers.progression.snapshot = Self.snapshot()
        let panel = try Self.panel(providers: providers)
        panel.startInspecting()
        defer { panel.stopInspecting() }

        panel.characterSection.experienceControl.stringValue = "750"
        sendScriptsControl(panel.awardExperienceControl)
        #expect(providers.progression.awards == [750])

        panel.characterSection.attributeControl.selectItem(at: 2)
        sendScriptsControl(panel.chooseAttributeControl)
        #expect(providers.progression.picks == [.stamina])

        sendScriptsControl(panel.characterSection.addPerkPointControl)
        sendScriptsControl(panel.characterSection.removePerkPointControl)
        #expect(providers.progression.perkPointDeltas == [1, -1])

        panel.skillsSection.amountControl.stringValue = "12.5"
        sendScriptsControl(panel.advanceSkillControl)
        #expect(providers.progression.uses == [12.5])
        sendScriptsControl(panel.incrementSkillControl)
        #expect(providers.progression.incrementCount == 1)

        sendScriptsControl(panel.spendPerkPointControl)
        sendScriptsControl(panel.grantPerkControl)
        sendScriptsControl(panel.removePerkControl)
        #expect(providers.progression.spendCount == 1)
        #expect(providers.progression.grantCount == 1)
        #expect(providers.progression.revokeCount == 1)
    }

    /// The two skill popups are one selection: choosing a tree in the Perk Tree
    /// section moves the Skills section with it, because both write the
    /// provider rather than their own state.
    @Test
    func theTwoSkillPopupsShareOneSelection() throws {
        let providers = FakeWorldProviders()
        providers.progression.snapshot = Self.snapshot()
        let panel = try Self.panel(providers: providers)
        panel.startInspecting()
        defer { panel.stopInspecting() }

        panel.perkTreeSection.skillControl.selectItem(at: 2)
        sendScriptsControl(panel.perkTreeSection.skillControl)
        #expect(providers.progressionSkillSelection == 21)

        panel.skillsSection.refreshReadout()
        #expect(panel.skillsSection.skillControl.indexOfSelectedItem == 2)

        panel.perkTreeSection.nodeControl.selectItem(at: 1)
        sendScriptsControl(panel.perkTreeSection.nodeControl)
        #expect(providers.progressionNodeSelection == 7)
    }

    /// A negative or unparsable amount never reaches the provider: the field
    /// falls back to its documented default rather than sending a guess.
    @Test
    func amountFieldsClampAndFallBack() throws {
        let providers = FakeWorldProviders()
        let panel = try Self.panel(providers: providers)

        panel.characterSection.experienceControl.stringValue = "-40"
        #expect(panel.characterSection.experienceAmount == 0)
        panel.characterSection.experienceControl.stringValue = "Wabbajack"
        #expect(
            panel.characterSection.experienceAmount
                == ProgressionCharacterSection.defaultExperience
        )
        panel.skillsSection.amountControl.stringValue = "-1"
        #expect(panel.skillsSection.useAmount == 0)
        panel.skillsSection.amountControl.stringValue = ""
        #expect(panel.skillsSection.useAmount == ProgressionSkillsSection.defaultAmount)
    }
}

/// Thrown only to end a run early when the registry hands back something other
/// than a world inspector, which `Issue.record` has already reported.
enum ProgressionPanelError: Error {
    case notAWorldInspector
}
