// The reading half of the World > Progression panel: the skill lines, the
// selected skill's AVIF perk tree, and the PERK record behind the selected box.
// `PerkTreeIndex` answers "which box grants this perk?". The panel asks the
// opposite, so it reads the AVIF node run in `INAM` order directly.

import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyProgressionInterface
import OpenSkyWorldState

extension ProgressionCoordinator {
    public func skillInformation(_ index: Int32) -> ResolvedActorValueInformation? {
        information?.information(actorValueIndex: index)
    }

    /// Falls back to the vanilla table, so a line always names something.
    public func skillName(_ index: Int32) -> String {
        skillInformation(index)?.displayName ?? ActorValueIdentity.description(of: index)
    }

    /// The eighteen skills, in actor-value index order.
    func skillReadouts(runtime: SkillAdvancementRuntime) -> [SkillProgressReadout] {
        // A local copy, so the tree closure's reads do not overlap the
        // mutating call's access to `treeCounts`.
        var counts = treeCounts
        let owned = perks.runtime?.state(of: .player).owned ?? []
        let readouts = ActorValueIdentity.skillIndices.map { index in
            let tree = counts.counts(forSkill: index, owned: owned) { perkKeys(forSkill: $0) }
            return SkillProgressReadout(
                name: skillName(index),
                index: index,
                current: runtime.values.value(at: index, on: .player) ?? 0,
                base: runtime.level(ofSkill: index, on: .player),
                experience: runtime.experience(forSkill: index, on: .player),
                threshold: runtime.threshold(forSkill: index, on: .player),
                ownedPerks: tree.owned,
                treePerks: tree.total
            )
        }
        treeCounts = counts
        return readouts
    }

    /// One entry per box, in `INAM` order.
    public func perkTreeNodes(forSkill index: Int32) -> [PerkTreeNodeReadout] {
        guard let record = skillInformation(index) else { return [] }
        let plugin = record.sourcePlugin
        return record.information.perkTree.map { node in
            guard
                let link = node.perk,
                let resolved = perks.runtime?.perks.resolve(link, fromPlugin: plugin)
            else {
                // The entry node, or a `PNAM` with no PERK in this load order.
                // Named apart, so a dangling link does not pass for the entry.
                return PerkTreeNodeReadout(
                    node: node.index,
                    name: node.isRoot ? "(tree entry)" : "(unresolved perk)",
                    grantsNoPerk: true,
                    isOwned: false,
                    requiresParent: node.parentRequired,
                    connections: node.connections,
                    ownedRank: 0,
                    rankCount: 0,
                    refusal: nil
                )
            }
            return readout(of: resolved, node: node)
        }
    }

    /// Nil when the box grants nothing, as every tree's entry node does.
    public func perkInspection(node: UInt32, forSkill index: Int32) -> PerkInspection? {
        guard
            let key = perkKey(node: node, forSkill: index),
            let resolved = perks.runtime?.record(key)
        else { return nil }
        let data = resolved.record.data
        return PerkInspection(
            name: resolved.displayName,
            editorID: resolved.editorID ?? "-",
            formID: resolved.id.description,
            isPlayable: resolved.record.isPlayable,
            isTrait: data?.isTrait ?? false,
            isHidden: data?.isHidden ?? false,
            isOwned: perks.runtime?.owns(key, on: .player) ?? false,
            conditions: resolved.record.conditions.conditions.map {
                world?.conditionText($0) ?? ""
            },
            effects: resolved.effects.map(Self.effectText)
        )
    }

    public func perkKey(node: UInt32, forSkill index: Int32) -> ReferenceKey? {
        guard
            let record = skillInformation(index),
            let entry = record.information.perkTree.first(where: { $0.index == node }),
            let link = entry.perk,
            let resolved = perks.runtime?.perks.resolve(link, fromPlugin: record.sourcePlugin)
        else { return nil }
        return ReferenceKey(resolved: resolved.id)
    }

    public func selectedPerkKey() -> ReferenceKey? {
        perkKey(node: nodeSelection, forSkill: skillSelection)
    }

    func firstNode(forSkill index: Int32) -> UInt32 {
        skillInformation(index)?.information.perkTree.first?.index ?? 0
    }

    // MARK: - Private

    /// Every perk a skill's tree grants, in node order.
    private func perkKeys(forSkill index: Int32) -> [ReferenceKey] {
        guard let record = skillInformation(index) else { return [] }
        return record.information.perkTree.compactMap { node in
            guard
                let link = node.perk,
                let resolved = perks.runtime?.perks.resolve(link, fromPlugin: record.sourcePlugin)
            else { return nil }
            return ReferenceKey(resolved: resolved.id)
        }
    }

    private func readout(of resolved: ResolvedPerk, node: PerkTreeNode) -> PerkTreeNodeReadout {
        let key = ReferenceKey(resolved: resolved.id)
        let chain = perks.runtime?.perks.rankChain(from: resolved.id) ?? []
        return PerkTreeNodeReadout(
            node: node.index,
            name: resolved.displayName,
            grantsNoPerk: false,
            isOwned: perks.runtime?.owns(key, on: .player) ?? false,
            requiresParent: node.parentRequired,
            connections: node.connections,
            ownedRank: perks.runtime?.rank(inChainFrom: key, on: .player) ?? 0,
            rankCount: chain.count,
            refusal: perkSpendRefusal(for: key)
        )
    }

    /// The spell is the store's resolved name, not the raw link.
    private static func effectText(_ effect: ResolvedPerkEffect) -> String {
        var text = "\(effect.effect.type) rank \(effect.effect.displayRank)"
        switch effect.effect.data {
        case let .quest(quest, stage):
            text += ": quest \(quest?.description ?? "NULL") stage \(stage)"
        case .ability:
            text += ": ability \(effect.spellName ?? "NULL")"
        case let .entryPoint(payload):
            text += ": \(payload.entryPoint), \(payload.function)"
            if let data = effect.effect.functionData {
                text += " (\(data))"
            }
            if let spell = effect.spellName {
                text += ", spell \(spell)"
            }
        case .raw, nil:
            text += ": no readable DATA"
        }
        let tabs = effect.effect.conditionTabs.count
        return tabs > 0 ? text + ", \(tabs) condition tab(s)" : text
    }
}
