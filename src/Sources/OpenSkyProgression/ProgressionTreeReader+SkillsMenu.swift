// The skills menu's reads, from the same runtimes the readout uses. Names and
// descriptions resolve through the string tables when the app gave them.
// See docs/engine/skills-menu.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyProgressionInterface

extension ProgressionTreeReader {
    func skillsMenuPerks(forSkill index: Int32) -> [SkillsMenuPerk] {
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
                description: cardText(chain: chain, owned: owned, shown: shown),
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

    /// A perk with ranks left past an owned one shows both descriptions.
    private func cardText(chain: [ResolvedPerk], owned: Int, shown: ResolvedPerk) -> String {
        let next = text(shown.record.description, plugin: shown.sourcePlugin, kind: .dlstrings)
        guard owned > 0, owned < chain.count else { return next ?? "" }
        let current = chain[owned - 1]
        return texts.perkCardText(
            owned: text(current.record.description, plugin: current.sourcePlugin, kind: .dlstrings),
            next: next
        )
    }

    func skillDescription(_ index: Int32) -> String {
        skillInformation(index).flatMap {
            text($0.information.description, plugin: $0.sourcePlugin, kind: .dlstrings)
        } ?? ""
    }

    /// The first rank of the chain the player lacks, or nil when all are owned.
    func nextRank(of head: ReferenceKey) -> ReferenceKey? {
        guard
            let runtime = perks.runtime,
            let resolved = runtime.perks.perk(key: head) else { return nil }
        return runtime.perks.rankChain(from: resolved.id)
            .map { ReferenceKey(resolved: $0.id) }
            .first { !runtime.owns($0, on: .player) }
    }

    private func refusalText(forChainFrom head: ReferenceKey) -> String? {
        guard let next = nextRank(of: head) else { return "owned" }
        return perkSpendRefusal(for: next).map(\.readoutText)
    }

    private func requirement(of perk: ResolvedPerk) -> String {
        perk.requiredSkill.map {
            texts.requirementText(skill: displaySkillName($0.skill), level: $0.level)
        } ?? ""
    }

    func displaySkillName(_ index: Int32) -> String {
        let information = skillInformation(index)
        let name = information.flatMap { info in
            text(info.information.name, plugin: info.sourcePlugin, kind: .strings)
        }
        return name ?? skillName(index)
    }

    /// Inline text needs no tables, so a session without them still shows it.
    func text(_ value: LString?, plugin: String, kind: StringTable.Kind) -> String? {
        if case let .inline(string)? = value {
            return string
        }
        return strings?.scoped(to: plugin).resolve(value, kind: kind)
    }
}

nonisolated extension ResolvedPerk {
    /// The perk's own `GetBaseActorValue <skill> >= N` condition, as the card shows it.
    var requiredSkill: (skill: Int32, level: Int)? {
        for condition in record.conditions.conditions where condition.functionIndex == 277 {
            let skill = condition.parameter1.asInt32
            guard
                ActorValueIdentity.isSkill(index: skill),
                condition.comparison == .greaterThanOrEqual,
                case let .value(level) = condition.comparisonValue
            else { continue }
            return (skill, Int(level))
        }
        return nil
    }
}
