// Main-app progression inspection seam (issue #500, roadmap item 20.7): what
// the `World > Progression` panel is written against, so the panel stays
// independent of `GameViewController` while reaching the same engine calls the
// runtime uses.
//
// One snapshot value rather than a bag of protocol properties, for the reason
// `ActorValueControlSnapshot` is one: a readout has to be a pure function of a
// single engine observation. A level, the experience under it and the perk
// points it paid for are three numbers one level-up moves together, and three
// reads taken microseconds apart could show a level that has not been paid for.
//
// AppKit-free, so it compiles into `openskycli` alongside the app.

import Foundation

/// One of the eighteen skills, as the panel spells it.
nonisolated struct SkillProgressReadout: Equatable, Sendable {
    /// The AVIF record's name when the load order resolves one, else the
    /// vanilla actor-value name. Never empty.
    let name: String
    /// The vanilla actor-value index, which is what a control acts on.
    let index: Int32
    /// What the skill reads right now, fortify effects included.
    let current: Float
    /// The trained level, which is what advancement compares against.
    let base: Float
    /// Experience accumulated in the skill's `Skill Advance` slot.
    let experience: Float
    /// What the next skill level costs from here, or zero when this load order
    /// carries no `AVSK` parameters for the skill.
    let threshold: Float
    /// Perks the player owns out of this skill's tree, and how many boxes the
    /// tree has.
    let ownedPerks: Int
    let treePerks: Int
}

/// One box in the selected skill's AVIF perk tree.
nonisolated struct PerkTreeNodeReadout: Equatable, Sendable {
    /// The box's own `INAM` identity, which is what a connection addresses.
    let node: UInt32
    /// The perk the box grants, or the entry node's stated absence.
    let name: String
    /// True for a box no point can ever be spent on: the tree's entry node,
    /// which every vanilla tree has and which the first real box hangs from,
    /// and a box whose `PNAM` this load order carries no PERK for.
    let grantsNoPerk: Bool
    let isOwned: Bool
    /// Whether the box's `FNAM` asks for an owned parent.
    let requiresParent: Bool
    /// `INAM`s of the boxes this one draws a line to.
    let connections: [UInt32]
    /// How far along the box's `NNAM` rank chain the player has come, and how
    /// long that chain is.
    let ownedRank: Int
    let rankCount: Int
    /// Why a perk point cannot be spent here right now, or nil when it can.
    let refusal: PerkSpendRefusal?
}

/// The selected box's resolved PERK record: what a user checks a perk's
/// numbers against without leaving the panel.
nonisolated struct PerkInspection: Equatable, Sendable {
    let name: String
    let editorID: String
    let formID: String
    /// The record's own `DATA` flags, which are what decide whether a tree can
    /// ever offer the perk.
    let isPlayable: Bool
    let isTrait: Bool
    let isHidden: Bool
    let isOwned: Bool
    /// The record-level `CTDA` run — a perk's skill requirement lives here
    /// rather than in its header — one line per condition.
    let conditions: [String]
    /// One line per effect: its type, its rank, and the entry point, ability
    /// or quest stage it carries.
    let effects: [String]

    static let empty = PerkInspection(
        name: "—",
        editorID: "-",
        formID: "-",
        isPlayable: false,
        isTrait: false,
        isHidden: false,
        isOwned: false,
        conditions: [],
        effects: []
    )
}

/// One observation of the progression runtime.
nonisolated struct ProgressionControlSnapshot: Equatable, Sendable {
    /// False when no progression runtime is attached — no game data, or a demo
    /// scene. Every other field is then empty and the panel says so rather
    /// than showing a convincing zero.
    let isAvailable: Bool
    /// The character level `GetLevel` reports for the player.
    let level: Int
    /// Character experience banked toward the next level, and what that level
    /// costs from here.
    let experience: Float
    let experienceForNextLevel: Float
    let perkPoints: Int
    let pendingAttributePicks: Int
    /// Picks already made, oldest first, which is what a level-up screen lists.
    let attributePicks: [ActorValueKind]
    /// Skill points gained this session.
    let skillIncreases: Int
    /// Perks the player owns, across every tree and every quest grant.
    let ownedPerkCount: Int
    /// The eighteen skills, in actor-value index order.
    let skills: [SkillProgressReadout]
    /// Which skill the controls and the tree act on.
    let selectedSkill: Int32
    /// The selected skill's tree, in `INAM` order.
    let treeNodes: [PerkTreeNodeReadout]
    /// Which box the perk controls act on.
    let selectedNode: UInt32
    /// The selected box's record, or nil when the box grants nothing.
    let perk: PerkInspection?
    /// Human-readable result of the last panel action.
    let lastActionText: String

    /// The reading with no runtime attached.
    static let unavailable = ProgressionControlSnapshot(
        isAvailable: false,
        level: 1,
        experience: 0,
        experienceForNextLevel: 0,
        perkPoints: 0,
        pendingAttributePicks: 0,
        attributePicks: [],
        skillIncreases: 0,
        ownedPerkCount: 0,
        skills: [],
        selectedSkill: ActorValueIdentity.firstSkillIndex,
        treeNodes: [],
        selectedNode: 0,
        perk: nil,
        lastActionText: "Progression unavailable: no game data loaded."
    )

    /// The selected skill's line, or nil when the load order carries no AVIF
    /// record for it.
    var selectedSkillReadout: SkillProgressReadout? {
        skills.first { $0.index == selectedSkill }
    }

    /// The selected box, or nil when the tree carries none with that identity.
    var selectedNodeReadout: PerkTreeNodeReadout? {
        treeNodes.first { $0.node == selectedNode }
    }
}

@MainActor
protocol ProgressionControlProviding: AnyObject {
    var progressionControlSnapshot: ProgressionControlSnapshot { get }

    /// Which skill the skill controls and the perk tree act on, by vanilla
    /// actor-value index.
    var progressionSkillSelection: Int32 { get set }

    /// Which box of that skill's tree the perk controls act on, by `INAM`.
    var progressionNodeSelection: UInt32 { get set }

    /// Reports `amount` of skill use on the selected skill, which is
    /// `Game.AdvanceSkill`'s own unit and the same call every swing makes.
    ///
    /// - Returns: a human-readable outcome, which the panel shows verbatim.
    @discardableResult
    func advanceSelectedSkill(byUse amount: Float) -> String

    /// Raises the selected skill by a whole point, which is
    /// `Game.IncrementSkill`.
    ///
    /// - Returns: a human-readable outcome, which the panel shows verbatim.
    @discardableResult
    func incrementSelectedSkill() -> String

    /// Banks `amount` of character experience and spends it against the level
    /// curve, which is what a skill point does on the player's behalf.
    ///
    /// - Returns: a human-readable outcome, which the panel shows verbatim.
    @discardableResult
    func awardCharacterExperience(_ amount: Float) -> String

    /// Spends one owed attribute pick on `kind`.
    ///
    /// - Returns: a human-readable outcome, which the panel shows verbatim.
    @discardableResult
    func chooseAttributePick(_ kind: ActorValueKind) -> String

    /// Adds or removes perk points, which is `Game.ModPerkPoints`.
    ///
    /// - Returns: a human-readable outcome, which the panel shows verbatim.
    @discardableResult
    func changePerkPoints(by delta: Int) -> String

    /// Spends one perk point on the selected box, after the tree, the rank
    /// order and the perk's own conditions have all agreed.
    ///
    /// - Returns: a human-readable outcome, which the panel shows verbatim.
    @discardableResult
    func spendPointOnSelectedPerk() -> String

    /// Gives the player the selected box's perk outright, bypassing the point
    /// and the tree — the dev control behind reading what a perk does.
    ///
    /// - Returns: a human-readable outcome, which the panel shows verbatim.
    @discardableResult
    func grantSelectedPerk() -> String

    /// Takes the selected box's perk away again.
    ///
    /// - Returns: a human-readable outcome, which the panel shows verbatim.
    @discardableResult
    func revokeSelectedPerk() -> String
}
