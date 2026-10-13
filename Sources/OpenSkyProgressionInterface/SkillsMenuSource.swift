// What the skills menu reads from progression and asks of it: the player card, the
// eighteen skills, one skill's perk tree, and the three spends (attribute pick, perk,
// legendary). Values only, so the menu model stays pure. See docs/engine/skills-menu.md.

import Foundation
import OpenSkyGameData

/// The player card at the top and bottom of the menu.
nonisolated public struct SkillsMenuPlayer: Equatable, Sendable {
    public struct Meter: Equatable, Sendable {
        public let current: Float
        public let maximum: Float

        public init(current: Float, maximum: Float) {
            self.current = current
            self.maximum = maximum
        }
    }

    public let name: String
    public let race: String
    public let level: Int
    /// Experience toward the next level, 0 to 1.
    public let levelProgress: Float
    public let health: Meter
    public let magicka: Meter
    public let stamina: Meter
    public let perkPoints: Int
    public let pendingAttributePicks: Int

    public init(
        name: String, race: String, level: Int, levelProgress: Float, health: Meter,
        magicka: Meter, stamina: Meter, perkPoints: Int, pendingAttributePicks: Int
    ) {
        self.name = name
        self.race = race
        self.level = level
        self.levelProgress = levelProgress
        self.health = health
        self.magicka = magicka
        self.stamina = stamina
        self.perkPoints = perkPoints
        self.pendingAttributePicks = pendingAttributePicks
    }

    public static let empty = SkillsMenuPlayer(
        name: "", race: "", level: 1, levelProgress: 0, health: Meter(current: 0, maximum: 0),
        magicka: Meter(current: 0, maximum: 0), stamina: Meter(current: 0, maximum: 0),
        perkPoints: 0, pendingAttributePicks: 0
    )
}

nonisolated public struct SkillsMenuSkill: Equatable, Sendable {
    /// The vanilla actor-value index.
    public let index: Int32
    public let name: String
    public let description: String
    /// The current value, fortify included, as the ring shows it.
    public let level: Float
    /// Experience toward the next skill level, 0 to 1.
    public let progress: Float
    public let legendaryCount: Int
    public let canMakeLegendary: Bool

    public init(
        index: Int32, name: String, description: String, level: Float,
        progress: Float, legendaryCount: Int, canMakeLegendary: Bool
    ) {
        self.index = index
        self.name = name
        self.description = description
        self.level = level
        self.progress = progress
        self.legendaryCount = legendaryCount
        self.canMakeLegendary = canMakeLegendary
    }
}

/// One box of a skill's tree. The entry node is left out: it grants nothing.
nonisolated public struct SkillsMenuPerk: Equatable, Sendable {
    /// The AVIF `INAM`.
    public let node: UInt32
    public let name: String
    public let description: String
    /// "Requires One-Handed 20", or empty when the perk needs no skill level.
    public let requirement: String
    /// The box's place on the AVIF grid (`XNAM` plus `HNAM`, `YNAM` plus `VNAM`).
    public let gridX: Float
    public let gridY: Float
    /// Boxes this one draws a line to.
    public let connections: [UInt32]
    public let ownedRank: Int
    public let rankCount: Int
    /// Nil when a point buys the next rank now.
    public let refusal: String?

    public init(
        node: UInt32, name: String, description: String, requirement: String, gridX: Float,
        gridY: Float, connections: [UInt32], ownedRank: Int, rankCount: Int, refusal: String?
    ) {
        self.node = node
        self.name = name
        self.description = description
        self.requirement = requirement
        self.gridX = gridX
        self.gridY = gridY
        self.connections = connections
        self.ownedRank = ownedRank
        self.rankCount = rankCount
        self.refusal = refusal
    }

    public var isOwned: Bool {
        ownedRank > 0
    }
}

/// What a spend did, as text the menu shows.
nonisolated public enum SkillsMenuOutcome: Equatable, Sendable {
    case done(String)
    case refused(String)
}

@MainActor
public protocol SkillsMenuSource: AnyObject {
    var skillsMenuPlayer: SkillsMenuPlayer { get }
    /// The eighteen skills, in actor-value order.
    var skillsMenuSkills: [SkillsMenuSkill] { get }
    func skillsMenuPerks(forSkill index: Int32) -> [SkillsMenuPerk]
    func skillsMenuChooseAttribute(_ kind: ActorValueKind) -> SkillsMenuOutcome
    /// Buys the next rank of the box.
    func skillsMenuBuyPerk(node: UInt32, forSkill index: Int32) -> SkillsMenuOutcome
    func skillsMenuMakeLegendary(_ index: Int32) -> SkillsMenuOutcome
}
