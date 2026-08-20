// The reading half of the `World > Progression` panel seam (issue #500,
// roadmap item 20.7): the skill lines, the selected skill's AVIF perk tree, and
// the resolved PERK record behind the selected box.
//
// AppKit stays in this controller satellite; every value it builds is an engine
// struct that compiles into `openskycli` and is asserted on without a window.
// Split from `GameViewControllerProgressionPanel.swift` — the conformance and
// its actions — because the two together are past the file-length cap.
//
// ## Why the tree is read from AVIF rather than from PerkTreeIndex
//
// `PerkTreeIndex` maps a perk to the box that grants it, which is the question
// a spend asks. A panel asks the opposite one — "what boxes does Destruction
// have?" — and answering it from the index would mean a scan of every placement
// per refresh. The AVIF record already holds the node run in `INAM` order, so
// the panel reads it directly and asks the index only what it is for.

import AppKit

extension GameViewController {
    /// The AVIF record describing a vanilla actor value, when the session has
    /// an index to look it up in.
    func progressionInformation(forSkill index: Int32) -> ResolvedActorValueInformation? {
        progression.information?.information(actorValueIndex: index)
    }

    /// A skill's name as the load order spells it, falling back to the vanilla
    /// actor-value table so a line always names something.
    func progressionSkillName(_ index: Int32) -> String {
        progressionInformation(forSkill: index)?.displayName
            ?? ActorValueIdentity.description(of: index)
    }

    /// The eighteen skills, in actor-value index order.
    func progressionSkillReadouts(
        runtime: SkillAdvancementRuntime
    ) -> [SkillProgressReadout] {
        ActorValueIdentity.skillIndices.map { index in
            let tree = progressionPerkKeys(forSkill: index)
            let owned = perks.runtime.map { perks in
                tree.count { perks.owns($0, on: .player) }
            } ?? 0
            return SkillProgressReadout(
                name: progressionSkillName(index),
                index: index,
                current: actorValues.runtime?.value(at: index, on: .player) ?? 0,
                base: runtime.level(ofSkill: index, on: .player),
                experience: runtime.experience(forSkill: index, on: .player),
                threshold: runtime.threshold(forSkill: index, on: .player),
                ownedPerks: owned,
                treePerks: tree.count
            )
        }
    }

    /// The selected skill's tree, one entry per box in `INAM` order.
    func progressionPerkTreeNodes(forSkill index: Int32) -> [PerkTreeNodeReadout] {
        guard let record = progressionInformation(forSkill: index) else { return [] }
        let plugin = record.sourcePlugin
        return record.information.perkTree.map { node in
            guard
                let link = node.perk,
                let resolved = perks.runtime?.perks.resolve(link, fromPlugin: plugin)
            else {
                // Either the tree's entry node or a `PNAM` this load order
                // carries no PERK for. Both are boxes no point can buy, and
                // they are named apart so a dangling link is not mistaken for
                // the entry every tree has.
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

    /// The resolved PERK record behind one box, or nil when the box grants
    /// nothing — which is what every tree's entry node does.
    func progressionPerkInspection(
        node: UInt32,
        forSkill index: Int32
    ) -> PerkInspection? {
        guard
            let key = progressionPerkKey(node: node, forSkill: index),
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
                RuntimeStateConditionRunner.describe(
                    $0, registry: ConditionFunctionRegistry.standard
                )
            },
            effects: resolved.effects.map(Self.effectText)
        )
    }

    /// The perk one box grants, by the plugin-relative link the AVIF node
    /// carries.
    func progressionPerkKey(node: UInt32, forSkill index: Int32) -> ReferenceKey? {
        guard
            let record = progressionInformation(forSkill: index),
            let entry = record.information.perkTree.first(where: { $0.index == node }),
            let link = entry.perk,
            let resolved = perks.runtime?.perks.resolve(
                link, fromPlugin: record.sourcePlugin
            )
        else { return nil }
        return ReferenceKey(resolved: resolved.id)
    }

    /// The box the perk controls act on right now.
    func progressionSelectedPerkKey() -> ReferenceKey? {
        progressionPerkKey(
            node: progression.nodeSelection, forSkill: progression.skillSelection
        )
    }

    /// The first box of a skill's tree, which is what the node selection lands
    /// on when the skill changes under it.
    func progressionFirstNode(forSkill index: Int32) -> UInt32 {
        progressionInformation(forSkill: index)?.information.perkTree.first?.index ?? 0
    }

    // MARK: - Private

    /// Every perk a skill's tree grants, in node order.
    private func progressionPerkKeys(forSkill index: Int32) -> [ReferenceKey] {
        guard let record = progressionInformation(forSkill: index) else { return [] }
        return record.information.perkTree.compactMap { node in
            guard
                let link = node.perk,
                let resolved = perks.runtime?.perks.resolve(
                    link, fromPlugin: record.sourcePlugin
                )
            else { return nil }
            return ReferenceKey(resolved: resolved.id)
        }
    }

    private func readout(
        of resolved: ResolvedPerk,
        node: PerkTreeNode
    ) -> PerkTreeNodeReadout {
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

    /// One effect line: what it does, and the entry point, ability or quest
    /// stage it carries. The spell is the store's resolved name rather than the
    /// raw link, which is the whole reason the panel reads `ResolvedPerk`.
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
