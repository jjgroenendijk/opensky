// The progression readout lines (issue #500, roadmap item 20.7), asserted in
// the engine target without a window — which is why they are formatted there
// rather than in the panel sections.
//
// What each case pins is the thing a reader of the panel has to be able to tell
// apart: a level that has been paid for from one that has not, a skill's
// trained base from its fortified value, and a box that is unavailable from one
// that is unavailable *for a stated reason*.

@testable import opensky
import Testing

struct ProgressionReadoutTests {
    @Test
    func theCharacterLineSpellsTheLevelAndWhatIsUnspent() {
        let snapshot = makeProgressionSnapshot(
            level: 7,
            experience: 240,
            experienceForNextLevel: 900,
            perkPoints: 3,
            pendingAttributePicks: 2
        )
        let text = ProgressionControlReadout.characterText(for: snapshot)
        #expect(text == "Character: level 7 — 240/900 XP  3 perk point(s)"
            + "  2 attribute pick(s) owed")
    }

    /// The picks line counts what each attribute was chosen for, which is the
    /// history a level-up screen lists — the ten points a pick granted live in
    /// the actor value's base offset, not here.
    @Test
    func thePicksLineCountsEachAttribute() {
        let snapshot = makeProgressionSnapshot(
            attributePicks: [.health, .stamina, .health],
            skillIncreases: 9,
            ownedPerkCount: 4
        )
        let text = ProgressionControlReadout.picksText(for: snapshot)
        #expect(text == "Picks: HP 2  MP 0  SP 1"
            + "  — 9 skill point(s) this session, 4 perk(s) owned")
    }

    /// A skill line carries the live value and the trained base separately: a
    /// fortified skill is not a trained one, and advancement compares against
    /// the base.
    @Test
    func aSkillLineSeparatesTheLiveValueFromTheTrainedBase() {
        let snapshot = makeProgressionSnapshot(
            skills: [
                makeSkillReadout(
                    name: "One-handed", index: 6, current: 45, base: 25,
                    experience: 30, threshold: 120, ownedPerks: 2, treePerks: 9
                )
            ],
            selectedSkill: 6
        )
        let text = ProgressionControlReadout.skillsText(for: snapshot)
        #expect(text.contains("Skills (1):"))
        #expect(text.contains("> One-handed"))
        #expect(text.contains("45.0 (base  25.0)"))
        #expect(text.contains("30.0/ 120.0 XP"))
        #expect(text.contains("perks 2/9"))
    }

    /// The skills block closes with what the count cache behind those lines is
    /// doing, which is how the reuse issue #556 added is read from the panel.
    @Test
    func theSkillsBlockClosesWithTheCacheLine() {
        let snapshot = makeProgressionSnapshot(
            skills: [makeSkillReadout(name: "One-handed", index: 6)],
            perkTreeCache: PerkTreeCacheReadout(
                skillCount: 18, treeCount: 18, countCount: 18, reuseCount: 342
            ),
            selectedSkill: 6
        )
        #expect(
            ProgressionControlReadout.skillsText(for: snapshot).hasSuffix(
                "Perk tree cache: 18 skill(s), 18 tree(s) resolved, 18 counted, 342 reused"
            )
        )
    }

    /// Every refusal reads as the rule that refused it, because each is
    /// something a level-up screen has to say out loud rather than a greyed-out
    /// button with no reason.
    @Test
    func everyRefusalSpellsItsOwnRule() {
        let perk = ReferenceKey.plugin(name: "test.esm", objectID: 0x0100)
        #expect(
            ProgressionControlReadout.description(of: .notPlayable) == "not playable"
        )
        #expect(ProgressionControlReadout.description(of: .alreadyOwned) == "owned")
        #expect(
            ProgressionControlReadout.description(of: .notInPerkTree) == "in no perk tree"
        )
        #expect(
            ProgressionControlReadout.description(of: .parentMissing)
                == "needs an owned parent"
        )
        #expect(
            ProgressionControlReadout.description(of: .unmetCondition)
                == "its own conditions do not hold"
        )
        #expect(
            ProgressionControlReadout.description(of: .previousRankMissing(perk))
                .hasPrefix("needs the rank below")
        )
        #expect(
            ProgressionControlReadout.description(of: .unresolvedPerk)
                == "no PERK record in this load order"
        )
    }

    /// A tree line carries the connections that are the tree's meaning, and
    /// prints a rank only where there is a chain to be part of.
    @Test
    func aTreeLineCarriesConnectionsAndOnlyMeaningfulRanks() {
        let snapshot = makeProgressionSnapshot(
            selectedSkill: 6,
            treeNodes: [
                makePerkTreeNode(
                    node: 0, name: "(tree entry)", grantsNoPerk: true,
                    requiresParent: false, connections: [7], rankCount: 0
                ),
                makePerkTreeNode(
                    node: 7, name: "Armsman", connections: [1, 2],
                    ownedRank: 2, rankCount: 5, refusal: .parentMissing
                )
            ],
            selectedNode: 7
        )
        let text = ProgressionControlReadout.perkTreeText(for: snapshot)
        #expect(text.contains("(2 nodes):"))
        #expect(
            text.contains("  #0 (tree entry) — grants no perk, parent optional, lines to [7]")
        )
        #expect(
            text.contains(
                "> #7 Armsman (rank 2/5) — needs an owned parent, parent required,"
                    + " lines to [1, 2]"
            )
        )
    }

    /// The selected box's record: its flags, its own conditions and its
    /// effects, each on its own line.
    @Test
    func theSelectedPerkPrintsItsFlagsConditionsAndEffects() {
        let snapshot = makeProgressionSnapshot(
            perk: PerkInspection(
                name: "Armsman",
                editorID: "Armsman00",
                formID: "Skyrim.esm:000BABE4",
                isPlayable: true,
                isTrait: false,
                isHidden: false,
                isOwned: false,
                conditions: ["GetBaseActorValue OneHanded >= 20.0"],
                effects: ["entry point rank 1: Mod Attack Damage (35), multiply value"]
            )
        )
        let text = ProgressionControlReadout.perkText(for: snapshot)
        #expect(text.contains("Armsman [Armsman00] Skyrim.esm:000BABE4 — not owned, playable"))
        #expect(text.contains("  conditions (1):"))
        #expect(text.contains("    GetBaseActorValue OneHanded >= 20.0"))
        #expect(text.contains("  effects (1):"))
        #expect(text.contains("Mod Attack Damage (35)"))
    }

    /// A box that grants nothing says so rather than showing an empty record.
    @Test
    func anEntryNodeSaysItGrantsNothing() {
        let text = ProgressionControlReadout.perkText(for: makeProgressionSnapshot())
        #expect(text == "Selected perk: none — this box grants no perk.")
    }

    /// With no runtime attached every line reports the absence rather than a
    /// convincing zero.
    @Test
    func everyLineReportsAnAbsentRuntime() {
        let snapshot = ProgressionControlSnapshot.unavailable
        #expect(ProgressionControlReadout.characterText(for: snapshot).hasSuffix("unavailable"))
        #expect(ProgressionControlReadout.picksText(for: snapshot).hasSuffix("unavailable"))
        #expect(ProgressionControlReadout.skillsText(for: snapshot).hasSuffix("unavailable"))
        #expect(ProgressionControlReadout.perkTreeText(for: snapshot).hasSuffix("unavailable"))
        #expect(ProgressionControlReadout.perkText(for: snapshot).hasSuffix("unavailable"))
        #expect(ProgressionControlReadout.controlsText(for: snapshot).hasSuffix("unavailable"))
    }

    /// One granted use prints what it was worth, and says out loud when it
    /// bought a skill level and a character level with it.
    @Test
    func theAdvanceLineNamesWhatTheUseBought() {
        let quiet = SkillAdvanceReport(
            skill: 6, experience: 6.3, previousLevel: 20, level: 20,
            carriedExperience: 12.6, characterExperience: 0
        )
        #expect(
            ProgressionControlReadout.advanceText(quiet, skillName: "One-handed")
                == "One-handed: +6.3 XP, 13 banked."
        )

        let leveled = SkillAdvanceReport(
            skill: 6, experience: 60, previousLevel: 20, level: 21,
            carriedExperience: 4, characterExperience: 32,
            levelUp: PlayerLevelUpReport(
                previousLevel: 3, level: 4, carriedExperience: 12,
                perkPoints: 1, pendingAttributePicks: 1
            )
        )
        let text = ProgressionControlReadout.advanceText(leveled, skillName: "One-handed")
        #expect(text.contains("level 20 to 21, +32 character XP"))
        #expect(text.hasSuffix("character level 3 to 4."))
    }
}
