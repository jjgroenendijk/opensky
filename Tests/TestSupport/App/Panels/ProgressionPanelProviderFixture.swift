// Snapshot builder for the World > Progression seam (issue #500), shared by the
// panel suite and by the M20 acceptance suite.
//
// `ProgressionControlSnapshot` is immutable by design and its memberwise
// initializer takes sixteen arguments, so a test that wants one non-zero field
// would otherwise have to spell out the other fifteen.

import AppKit
@testable import opensky

nonisolated func makeProgressionSnapshot(
    isAvailable: Bool = true,
    level: Int = 1,
    experience: Float = 0,
    experienceForNextLevel: Float = 0,
    perkPoints: Int = 0,
    pendingAttributePicks: Int = 0,
    attributePicks: [ActorValueKind] = [],
    skillIncreases: Int = 0,
    ownedPerkCount: Int = 0,
    skills: [SkillProgressReadout] = [],
    perkTreeCache: PerkTreeCacheReadout = .empty,
    selectedSkill: Int32 = ActorValueIdentity.firstSkillIndex,
    treeNodes: [PerkTreeNodeReadout] = [],
    selectedNode: UInt32 = 0,
    perk: PerkInspection? = nil,
    lastActionText: String = "No leveling action yet."
) -> ProgressionControlSnapshot {
    ProgressionControlSnapshot(
        isAvailable: isAvailable,
        level: level,
        experience: experience,
        experienceForNextLevel: experienceForNextLevel,
        perkPoints: perkPoints,
        pendingAttributePicks: pendingAttributePicks,
        attributePicks: attributePicks,
        skillIncreases: skillIncreases,
        ownedPerkCount: ownedPerkCount,
        skills: skills,
        perkTreeCache: perkTreeCache,
        selectedSkill: selectedSkill,
        treeNodes: treeNodes,
        selectedNode: selectedNode,
        perk: perk,
        lastActionText: lastActionText
    )
}

/// One skill line, defaulted so a test states only what it is about.
nonisolated func makeSkillReadout(
    name: String,
    index: Int32,
    current: Float = 20,
    base: Float = 20,
    experience: Float = 0,
    threshold: Float = 100,
    ownedPerks: Int = 0,
    treePerks: Int = 0
) -> SkillProgressReadout {
    SkillProgressReadout(
        name: name,
        index: index,
        current: current,
        base: base,
        experience: experience,
        threshold: threshold,
        ownedPerks: ownedPerks,
        treePerks: treePerks
    )
}

/// One perk-tree box, defaulted the same way.
nonisolated func makePerkTreeNode(
    node: UInt32,
    name: String,
    grantsNoPerk: Bool = false,
    isOwned: Bool = false,
    requiresParent: Bool = true,
    connections: [UInt32] = [],
    ownedRank: Int = 0,
    rankCount: Int = 1,
    refusal: PerkSpendRefusal? = nil
) -> PerkTreeNodeReadout {
    PerkTreeNodeReadout(
        node: node,
        name: name,
        grantsNoPerk: grantsNoPerk,
        isOwned: isOwned,
        requiresParent: requiresParent,
        connections: connections,
        ownedRank: ownedRank,
        rankCount: rankCount,
        refusal: refusal
    )
}
