// The progression reads: the skill lines, a skill's AVIF perk tree, the PERK record
// behind a box, and whether a point can be spent on it.
// `PerkTreeIndex` answers "which box grants this perk?". The readout asks the
// opposite, so it reads the AVIF node run in `INAM` order directly.

import Foundation
import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyProgressionInterface

/// Part of `ProgressionCoordinator`: answers from the AVIF index, the perk runtime, and
/// the string tables, and changes nothing but its caches.
@MainActor
final class ProgressionTreeReader {
    let perks: PerkCoordinator
    /// The AVIF index the readout browses a skill's perk tree out of.
    let information: ActorValueInformationStore?
    /// Where each perk sits in a skill's tree. Empty without game data, and
    /// every spend is then refused with `.notInPerkTree`.
    let trees: PerkTreeIndex
    private let world: any ProgressionWorld
    let texts: ProgressionTexts
    /// The readout asks twice a second; walking eighteen trees each time is
    /// about nine hundred record lookups for numbers that rarely move.
    private var treeCounts = PerkTreeCountCache()
    private var cachedStrings: LocalizedStrings??

    init(
        perks: PerkCoordinator, world: any ProgressionWorld,
        data: (information: ActorValueInformationStore, perks: PerkStore)?,
        texts: ProgressionTexts = .vanilla
    ) {
        self.perks = perks
        self.world = world
        self.texts = texts
        information = data?.information
        trees = data.map { PerkTreeIndex(information: $0.information, perks: $0.perks) } ?? .empty
    }

    /// Loaded on first use, because loading reads every table file.
    var strings: LocalizedStrings? {
        if let cachedStrings {
            return cachedStrings
        }
        let loaded = world.localizedStrings()
        cachedStrings = .some(loaded)
        return loaded
    }

    var countsReadout: PerkTreeCacheReadout {
        treeCounts.readout
    }

    func invalidateCounts() {
        treeCounts.invalidate()
    }

    func skillInformation(_ index: Int32) -> ResolvedActorValueInformation? {
        if let tree = BeastPerkTree(actorValueIndex: index) {
            return information?.information(editorID: tree.informationEditorID)
        }
        return information?.information(actorValueIndex: index)
    }

    /// Falls back to the vanilla table, so a line always names something.
    func skillName(_ index: Int32) -> String {
        skillInformation(index)?.displayName ?? ActorValueIdentity.description(of: index)
    }

    /// The eighteen skills, in actor-value index order.
    func skillReadouts(
        runtime: SkillAdvancementRuntime, progress: PlayerProgressState?
    ) -> [SkillProgressReadout] {
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
                treePerks: tree.total,
                legendaryCount: progress?.legendaryCount(ofSkill: index) ?? 0
            )
        }
        treeCounts = counts
        return readouts
    }

    /// One entry per box, in `INAM` order.
    func perkTreeNodes(forSkill index: Int32) -> [PerkTreeNodeReadout] {
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
    func perkInspection(node: UInt32, forSkill index: Int32) -> PerkInspection? {
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
                world.conditionText($0)
            },
            effects: resolved.effects.map(\.readoutText)
        )
    }

    func perkKey(node: UInt32, forSkill index: Int32) -> ReferenceKey? {
        guard
            let record = skillInformation(index),
            let entry = record.information.perkTree.first(where: { $0.index == node }),
            let link = entry.perk,
            let resolved = perks.runtime?.perks.resolve(link, fromPlugin: record.sourcePlugin)
        else { return nil }
        return ReferenceKey(resolved: resolved.id)
    }

    func firstNode(forSkill index: Int32) -> UInt32 {
        skillInformation(index)?.information.perkTree.first?.index ?? 0
    }

    /// Every perk a skill's tree grants, in node order.
    func perkKeys(forSkill index: Int32) -> [ReferenceKey] {
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
            requiresParent: node.parentRequired,
            connections: node.connections,
            ownedRank: perks.runtime?.rank(inChainFrom: key, on: .player) ?? 0,
            rankCount: chain.count,
            refusal: perkSpendRefusal(for: key)
        )
    }

    /// Every owned rank of every box in the tree, rank by rank.
    func ownedTreePerks(ofSkill index: Int32) -> [ReferenceKey] {
        guard let runtime = perks.runtime else { return [] }
        let owned = Set(runtime.state(of: .player).owned)
        return perkKeys(forSkill: index).flatMap { head -> [ReferenceKey] in
            guard let resolved = runtime.perks.perk(key: head) else { return [] }
            return runtime.perks.rankChain(from: resolved.id)
                .map { ReferenceKey(resolved: $0.id) }
                .filter(owned.contains)
        }
    }

    /// The perk's name, or the key when the runtime has no record of it.
    func perkName(_ key: ReferenceKey) -> String {
        perks.runtime?.record(key)?.displayName ?? key.description
    }

    func hasPerkTree(_ index: Int32) -> Bool {
        skillInformation(index)?.information.hasPerkTree == true
    }

    /// Nil when the player can buy `perk` now.
    func perkSpendRefusal(for perk: ReferenceKey) -> PerkSpendRefusal? {
        spendRefusal(for: perk, on: .player)
    }

    func spendRefusal(
        for perk: ReferenceKey,
        on holder: ActorValueHolder
    ) -> PerkSpendRefusal? {
        guard let runtime = perks.runtime else { return .unresolvedPerk }
        let validator = PerkTreeSpendValidator(
            runtime: runtime, trees: trees, conditionRegistry: runtime.conditions.functions
        )
        return validator.refusal(
            for: perk, on: holder, conditions: world.conditionContext()
        )
    }
}

nonisolated extension ResolvedPerkEffect {
    /// The spell is the store's resolved name, not the raw link.
    var readoutText: String {
        let effect = self
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
