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
import OpenSkyFormatsESM
import OpenSkyGameData

/// One of the eighteen skills, as the panel spells it.
nonisolated public struct SkillProgressReadout: Equatable, Sendable {
    /// The AVIF record's name when the load order resolves one, else the
    /// vanilla actor-value name. Never empty.
    public let name: String
    /// The vanilla actor-value index, which is what a control acts on.
    public let index: Int32
    /// What the skill reads right now, fortify effects included.
    public let current: Float
    /// The trained level, which is what advancement compares against.
    public let base: Float
    /// Experience accumulated in the skill's `Skill Advance` slot.
    public let experience: Float
    /// What the next skill level costs from here, or zero when this load order
    /// carries no `AVSK` parameters for the skill.
    public let threshold: Float
    /// Perks the player owns out of this skill's tree, and how many boxes the
    /// tree has.
    public let ownedPerks: Int
    public let treePerks: Int

    public init(
        name: String,
        index: Int32,
        current: Float,
        base: Float,
        experience: Float,
        threshold: Float,
        ownedPerks: Int,
        treePerks: Int
    ) {
        self.name = name
        self.index = index
        self.current = current
        self.base = base
        self.experience = experience
        self.threshold = threshold
        self.ownedPerks = ownedPerks
        self.treePerks = treePerks
    }
}

/// One box in the selected skill's AVIF perk tree.
nonisolated public struct PerkTreeNodeReadout: Equatable, Sendable {
    /// The box's own `INAM` identity, which is what a connection addresses.
    public let node: UInt32
    /// The perk the box grants, or the entry node's stated absence.
    public let name: String
    /// True for a box no point can ever be spent on: the tree's entry node,
    /// which every vanilla tree has and which the first real box hangs from,
    /// and a box whose `PNAM` this load order carries no PERK for.
    public let grantsNoPerk: Bool
    public let isOwned: Bool
    /// Whether the box's `FNAM` asks for an owned parent.
    public let requiresParent: Bool
    /// `INAM`s of the boxes this one draws a line to.
    public let connections: [UInt32]
    /// How far along the box's `NNAM` rank chain the player has come, and how
    /// long that chain is.
    public let ownedRank: Int
    public let rankCount: Int
    /// Why a perk point cannot be spent here right now, or nil when it can.
    public let refusal: PerkSpendRefusal?

    public init(
        node: UInt32,
        name: String,
        grantsNoPerk: Bool,
        isOwned: Bool,
        requiresParent: Bool,
        connections: [UInt32],
        ownedRank: Int,
        rankCount: Int,
        refusal: PerkSpendRefusal?
    ) {
        self.node = node
        self.name = name
        self.grantsNoPerk = grantsNoPerk
        self.isOwned = isOwned
        self.requiresParent = requiresParent
        self.connections = connections
        self.ownedRank = ownedRank
        self.rankCount = rankCount
        self.refusal = refusal
    }
}

/// The selected box's resolved PERK record: what a user checks a perk's
/// numbers against without leaving the panel.
nonisolated public struct PerkInspection: Equatable, Sendable {
    public let name: String
    public let editorID: String
    public let formID: String
    /// The record's own `DATA` flags, which are what decide whether a tree can
    /// ever offer the perk.
    public let isPlayable: Bool
    public let isTrait: Bool
    public let isHidden: Bool
    public let isOwned: Bool
    /// The record-level `CTDA` run — a perk's skill requirement lives here
    /// rather than in its header — one line per condition.
    public let conditions: [String]
    /// One line per effect: its type, its rank, and the entry point, ability
    /// or quest stage it carries.
    public let effects: [String]

    public static let empty = PerkInspection(
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

    public init(
        name: String,
        editorID: String,
        formID: String,
        isPlayable: Bool,
        isTrait: Bool,
        isHidden: Bool,
        isOwned: Bool,
        conditions: [String],
        effects: [String]
    ) {
        self.name = name
        self.editorID = editorID
        self.formID = formID
        self.isPlayable = isPlayable
        self.isTrait = isTrait
        self.isHidden = isHidden
        self.isOwned = isOwned
        self.conditions = conditions
        self.effects = effects
    }
}

/// One observation of the progression runtime.
nonisolated public struct ProgressionControlSnapshot: Equatable, Sendable {
    /// False when no progression runtime is attached — no game data, or a demo
    /// scene. Every other field is then empty and the panel says so rather
    /// than showing a convincing zero.
    public let isAvailable: Bool
    /// The character level `GetLevel` reports for the player.
    public let level: Int
    /// Character experience banked toward the next level, and what that level
    /// costs from here.
    public let experience: Float
    public let experienceForNextLevel: Float
    public let perkPoints: Int
    public let pendingAttributePicks: Int
    /// Picks already made, oldest first, which is what a level-up screen lists.
    public let attributePicks: [ActorValueKind]
    /// Skill points gained this session.
    public let skillIncreases: Int
    /// Perks the player owns, across every tree and every quest grant.
    public let ownedPerkCount: Int
    /// The eighteen skills, in actor-value index order.
    public let skills: [SkillProgressReadout]
    /// What the per-skill perk-tree cache behind those lines holds and how much
    /// of this tick's reading it served without touching the records
    /// (issue #556).
    public let perkTreeCache: PerkTreeCacheReadout
    /// Which skill the controls and the tree act on.
    public let selectedSkill: Int32
    /// The selected skill's tree, in `INAM` order.
    public let treeNodes: [PerkTreeNodeReadout]
    /// Which box the perk controls act on.
    public let selectedNode: UInt32
    /// The selected box's record, or nil when the box grants nothing.
    public let perk: PerkInspection?
    /// Human-readable result of the last panel action.
    public let lastActionText: String

    /// The reading with no runtime attached.
    public static let unavailable = ProgressionControlSnapshot(
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
        perkTreeCache: .empty,
        selectedSkill: ActorValueIdentity.firstSkillIndex,
        treeNodes: [],
        selectedNode: 0,
        perk: nil,
        lastActionText: "Progression unavailable: no game data loaded."
    )

    /// The selected skill's line, or nil when the load order carries no AVIF
    /// record for it.
    public var selectedSkillReadout: SkillProgressReadout? {
        skills.first { $0.index == selectedSkill }
    }

    /// The selected box, or nil when the tree carries none with that identity.
    public var selectedNodeReadout: PerkTreeNodeReadout? {
        treeNodes.first { $0.node == selectedNode }
    }

    public init(
        isAvailable: Bool,
        level: Int,
        experience: Float,
        experienceForNextLevel: Float,
        perkPoints: Int,
        pendingAttributePicks: Int,
        attributePicks: [ActorValueKind],
        skillIncreases: Int,
        ownedPerkCount: Int,
        skills: [SkillProgressReadout],
        perkTreeCache: PerkTreeCacheReadout,
        selectedSkill: Int32,
        treeNodes: [PerkTreeNodeReadout],
        selectedNode: UInt32,
        perk: PerkInspection?,
        lastActionText: String
    ) {
        self.isAvailable = isAvailable
        self.level = level
        self.experience = experience
        self.experienceForNextLevel = experienceForNextLevel
        self.perkPoints = perkPoints
        self.pendingAttributePicks = pendingAttributePicks
        self.attributePicks = attributePicks
        self.skillIncreases = skillIncreases
        self.ownedPerkCount = ownedPerkCount
        self.skills = skills
        self.perkTreeCache = perkTreeCache
        self.selectedSkill = selectedSkill
        self.treeNodes = treeNodes
        self.selectedNode = selectedNode
        self.perk = perk
        self.lastActionText = lastActionText
    }
}

@MainActor
public protocol ProgressionControlProviding: AnyObject {
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
