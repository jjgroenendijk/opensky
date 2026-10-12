// The skills menu (Quick Stats) as a value: the level-up pick, the ring of eighteen
// skills, one skill's perk tree, and the legendary question. The coordinator does the
// spends and hands fresh values back. See docs/engine/skills-menu.md.

import Foundation
import OpenSkyGameData
import OpenSkyProgressionInterface

nonisolated public struct SkillsMenuModel: Equatable, Sendable {
    public enum Page: Equatable, Sendable {
        case levelUp
        case skills
        case perks
        case legendary(ConfirmationModel)
    }

    public enum Action: Equatable, Sendable {
        case chooseAttribute(ActorValueKind)
        case buyPerk(node: UInt32, skill: Int32)
        case makeLegendary(Int32)
        /// The coordinator loads the tree with `setPerks(_:)`.
        case showTree(Int32)
        case close
    }

    /// The constellations around the ring, magic first, in the order the Dragonborn
    /// altar numbers them (`DLC2MiraakAltarScript`).
    public static let ringOrder: [Int32] = [
        21, 19, 20, 22, 18, 23, 10, 11, 9, 7, 6, 8, 12, 15, 14, 13, 17, 16
    ]
    /// Left to right, as the three buttons of `levelupmenu.swf` stand.
    public static let attributes: [ActorValueKind] = [.magicka, .health, .stamina]

    public private(set) var page: Page
    public private(set) var player: SkillsMenuPlayer
    /// In ring order.
    public private(set) var skills: [SkillsMenuSkill]
    public private(set) var perks: [SkillsMenuPerk] = []
    public private(set) var skillPosition = 0
    public private(set) var perkPosition = 0
    public private(set) var attributePosition = 1
    /// The last spend's answer, or why a key did nothing.
    public var message: String?

    public init(player: SkillsMenuPlayer, skills: [SkillsMenuSkill]) {
        self.player = player
        self.skills = Self.ringOrdered(skills)
        page = player.pendingAttributePicks > 0 ? .levelUp : .skills
    }

    public var selectedSkill: SkillsMenuSkill? {
        skills.indices.contains(skillPosition) ? skills[skillPosition] : nil
    }

    public var selectedPerk: SkillsMenuPerk? {
        perks.indices.contains(perkPosition) ? perks[perkPosition] : nil
    }

    public var selectedAttribute: ActorValueKind {
        Self.attributes[attributePosition]
    }

    /// Fresh values after a spend. The selection stays on the same skill and box.
    public mutating func refresh(player: SkillsMenuPlayer, skills: [SkillsMenuSkill]) {
        let skill = selectedSkill?.index
        self.player = player
        self.skills = Self.ringOrdered(skills)
        if let skill, let position = self.skills.firstIndex(where: { $0.index == skill }) {
            skillPosition = position
        }
        if page == .levelUp, player.pendingAttributePicks == 0 {
            page = .skills
        }
    }

    /// Enters the tree on its lowest box, the one a new character starts from.
    public mutating func setPerks(_ perks: [SkillsMenuPerk], keepSelection: Bool = false) {
        let node = keepSelection ? selectedPerk?.node : nil
        self.perks = perks
        let lowest = perks.indices.min { lhs, rhs in
            (perks[lhs].gridY, perks[lhs].gridX) < (perks[rhs].gridY, perks[rhs].gridX)
        }
        let kept = node.flatMap { node in perks.firstIndex { $0.node == node } }
        perkPosition = kept ?? lowest ?? 0
    }

    public mutating func handle(_ event: MenuInputEvent) -> Action? {
        switch page {
        case .levelUp: handleLevelUp(event)
        case .skills: handleSkills(event)
        case .perks: handlePerks(event)
        case let .legendary(confirmation): handleLegendary(event, confirmation)
        }
    }

    // MARK: - Pages

    private mutating func handleLevelUp(_ event: MenuInputEvent) -> Action? {
        switch event {
        case .move(.left), .move(.up):
            attributePosition = (attributePosition + 2) % 3
        case .move(.right), .move(.down):
            attributePosition = (attributePosition + 1) % 3
        case .button(.accept):
            return .chooseAttribute(selectedAttribute)
        case .button(.cancel):
            return .close
        default:
            break
        }
        return nil
    }

    private mutating func handleSkills(_ event: MenuInputEvent) -> Action? {
        guard !skills.isEmpty else { return event == .button(.cancel) ? .close : nil }
        switch event {
        case .move(.left):
            skillPosition = (skillPosition + skills.count - 1) % skills.count
        case .move(.right):
            skillPosition = (skillPosition + 1) % skills.count
        case .move(.up), .button(.accept):
            guard let skill = selectedSkill else { return nil }
            page = .perks
            return .showTree(skill.index)
        case .button(.cancel):
            return .close
        case .button(.yButton):
            askLegendary()
        default:
            break
        }
        return nil
    }

    private mutating func handlePerks(_ event: MenuInputEvent) -> Action? {
        switch event {
        case let .move(direction):
            if let next = nearestPerk(toward: direction) {
                perkPosition = next
            } else if direction == .down {
                page = .skills
            }
        case .button(.accept):
            guard let perk = selectedPerk, let skill = selectedSkill else { return nil }
            if let refusal = perk.refusal {
                message = refusal
                return nil
            }
            return .buyPerk(node: perk.node, skill: skill.index)
        case .button(.cancel):
            page = .skills
        case .button(.yButton):
            askLegendary()
        default:
            break
        }
        return nil
    }

    private mutating func handleLegendary(
        _ event: MenuInputEvent, _ confirmation: ConfirmationModel
    ) -> Action? {
        var confirmation = confirmation
        switch confirmation.handle(event) {
        case nil:
            page = .legendary(confirmation)
            return nil
        case .chose(0):
            page = .skills
            return selectedSkill.map { .makeLegendary($0.index) }
        case .chose, .cancelled:
            page = .skills
            return nil
        }
    }

    // MARK: - Helpers

    private mutating func askLegendary() {
        guard let skill = selectedSkill else { return }
        guard skill.canMakeLegendary else {
            message = "\(skill.name) must reach 100 to become legendary."
            return
        }
        page = .legendary(ConfirmationModel(
            question: "Make \(skill.name) legendary? It drops back to its starting level, "
                + "and every perk point spent in it is returned."
        ))
    }

    /// The closest box that way, with sideways distance counted twice, so up follows a
    /// branch before it jumps to a neighbour.
    private func nearestPerk(toward direction: MenuInputEvent.Direction) -> Int? {
        guard let current = selectedPerk else { return nil }
        let step: (forward: (SkillsMenuPerk) -> Float, side: (SkillsMenuPerk) -> Float) =
            switch direction {
            case .up: ({ $0.gridY - current.gridY }, { $0.gridX - current.gridX })
            case .down: ({ current.gridY - $0.gridY }, { $0.gridX - current.gridX })
            case .right: ({ $0.gridX - current.gridX }, { $0.gridY - current.gridY })
            case .left: ({ current.gridX - $0.gridX }, { $0.gridY - current.gridY })
            }
        return perks.indices
            .filter { step.forward(perks[$0]) > 0.01 }
            .min { score(perks[$0], step) < score(perks[$1], step) }
    }

    private func score(
        _ perk: SkillsMenuPerk,
        _ step: (forward: (SkillsMenuPerk) -> Float, side: (SkillsMenuPerk) -> Float)
    ) -> Float {
        step.forward(perk) + 2 * abs(step.side(perk))
    }

    private static func ringOrdered(_ skills: [SkillsMenuSkill]) -> [SkillsMenuSkill] {
        let ordered = ringOrder.compactMap { index in skills.first { $0.index == index } }
        return ordered + skills.filter { !ringOrder.contains($0.index) }
    }
}
