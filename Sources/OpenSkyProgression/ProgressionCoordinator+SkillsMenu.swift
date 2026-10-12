// The skills menu's reads and spends, answered from the same runtimes the panel uses.
// Names and descriptions resolve through the string tables when the app gave them.
// See docs/engine/skills-menu.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyProgressionInterface

extension ProgressionCoordinator: SkillsMenuSource {
    public var skillsMenuPlayer: SkillsMenuPlayer {
        guard let leveling else { return .empty }
        let state = leveling.state
        let identity = world?.playerIdentity() ?? (name: "", race: "")
        let needed = leveling.experienceForNextLevel
        return SkillsMenuPlayer(
            name: identity.name,
            race: identity.race,
            level: state.level,
            levelProgress: needed > 0 ? min(1, max(0, state.experience / needed)) : 0,
            health: meter(.health, leveling.values),
            magicka: meter(.magicka, leveling.values),
            stamina: meter(.stamina, leveling.values),
            perkPoints: state.perkPoints,
            pendingAttributePicks: state.pendingAttributePicks
        )
    }

    public var skillsMenuSkills: [SkillsMenuSkill] {
        guard let skills else { return [] }
        let state = leveling?.state ?? PlayerProgressState()
        return ActorValueIdentity.skillIndices.map { index in
            let threshold = skills.threshold(forSkill: index, on: .player)
            let experience = skills.experience(forSkill: index, on: .player)
            return SkillsMenuSkill(
                index: index,
                name: displaySkillName(index),
                description: skillInformation(index).flatMap {
                    text($0.information.description, plugin: $0.sourcePlugin, kind: .dlstrings)
                } ?? "",
                level: skills.values.value(at: index, on: .player) ?? 0,
                base: skills.level(ofSkill: index, on: .player),
                progress: threshold > 0 ? min(1, max(0, experience / threshold)) : 0,
                legendaryCount: state.legendaryCount(ofSkill: index),
                canMakeLegendary: legendaryRefusal(forSkill: index) == nil
            )
        }
    }

    public func skillsMenuPerks(forSkill index: Int32) -> [SkillsMenuPerk] {
        guard let record = skillInformation(index), let runtime = perks.runtime else { return [] }
        return record.information.perkTree.compactMap { node in
            guard
                let link = node.perk,
                let resolved = runtime.perks.resolve(link, fromPlugin: record.sourcePlugin)
            else { return nil }
            let key = ReferenceKey(resolved: resolved.id)
            let chain = runtime.perks.rankChain(from: resolved.id)
            let owned = runtime.rank(inChainFrom: key, on: .player)
            let shown = chain.indices.contains(owned) ? chain[owned] : resolved
            return SkillsMenuPerk(
                node: node.index,
                name: text(resolved.record.name, plugin: resolved.sourcePlugin, kind: .strings)
                    ?? resolved.displayName,
                description: text(
                    shown.record.description,
                    plugin: shown.sourcePlugin,
                    kind: .dlstrings
                )
                    ?? "",
                requirement: requirement(of: shown),
                gridX: Float(node.position.column) + node.position.horizontal,
                gridY: Float(node.position.row) + node.position.vertical,
                connections: node.connections,
                ownedRank: owned,
                rankCount: chain.count,
                refusal: refusalText(forChainFrom: key)
            )
        }
    }

    public func skillsMenuChooseAttribute(_ kind: ActorValueKind) -> SkillsMenuOutcome {
        switch chooseAttribute(kind) {
        case .success:
            let name = ActorValueIdentity.name(at: ActorValueIdentity.index(of: kind))
            return .done("\(name ?? "Attribute") increased.")
        case let .failure(error): return .refused(String(describing: error))
        }
    }

    public func skillsMenuBuyPerk(node: UInt32, forSkill index: Int32) -> SkillsMenuOutcome {
        guard let head = perkKey(node: node, forSkill: index), let next = nextRank(of: head) else {
            return .refused("Every rank is owned.")
        }
        switch spendPerkPoint(on: next) {
        case .success:
            treeCounts.invalidate()
            return .done("Perk added.")
        case let .failure(.perkRefused(refusal)):
            return .refused(ProgressionControlReadout.description(of: refusal))
        case let .failure(error): return .refused(String(describing: error))
        }
    }

    public func skillsMenuMakeLegendary(_ index: Int32) -> SkillsMenuOutcome {
        switch makeSkillLegendary(index) {
        case let .success(report):
            .done(
                "\(displaySkillName(index)) is legendary. "
                    + "\(report.refundedPoints) perk point(s) refunded."
            )
        case let .failure(refusal): .refused(String(describing: refusal))
        }
    }

    // MARK: - Private

    /// The first rank of the chain the player lacks, or nil when all are owned.
    private func nextRank(of head: ReferenceKey) -> ReferenceKey? {
        guard
            let runtime = perks.runtime,
            let resolved = runtime.perks.perk(key: head) else { return nil }
        return runtime.perks.rankChain(from: resolved.id)
            .map { ReferenceKey(resolved: $0.id) }
            .first { !runtime.owns($0, on: .player) }
    }

    private func refusalText(forChainFrom head: ReferenceKey) -> String? {
        guard let next = nextRank(of: head) else { return "owned" }
        return perkSpendRefusal(for: next).map(ProgressionControlReadout.description(of:))
    }

    /// The perk's own `GetBaseActorValue <skill> >= N` condition, as the card shows it.
    private func requirement(of perk: ResolvedPerk) -> String {
        for condition in perk.record.conditions.conditions where condition.functionIndex == 277 {
            let skill = condition.parameter1.asInt32
            guard
                ActorValueIdentity.isSkill(index: skill),
                condition.comparison == .greaterThanOrEqual,
                case let .value(level) = condition.comparisonValue
            else { continue }
            return "Requires \(displaySkillName(skill)) \(Int(level))"
        }
        return ""
    }

    func displaySkillName(_ index: Int32) -> String {
        let information = skillInformation(index)
        let name = information.flatMap { info in
            text(info.information.name, plugin: info.sourcePlugin, kind: .strings)
        }
        return name ?? skillName(index)
    }

    /// Inline text needs no tables, so a session without them still shows it.
    private func text(_ value: LString?, plugin: String, kind: StringTable.Kind) -> String? {
        if case let .inline(string)? = value {
            return string
        }
        return strings?.scoped(to: plugin).resolve(value, kind: kind)
    }

    private func meter(_ kind: ActorValueKind, _ values: any ActorValueAccess) -> SkillsMenuPlayer
        .Meter
    {
        SkillsMenuPlayer.Meter(
            current: values.current(of: .player)[kind],
            maximum: values.maximums(of: .player)[kind]
        )
    }
}
