// Actor template-chain resolution (milestone 5.1): follow NPC_ TPLT links
// through direct NPC_ targets and LVLN leveled lists, then resolve each
// appearance field to the chain record that actually provides it, driven by
// the per-record ACBS template flags. Never copies whole records: a field
// delegates upward only while its governing flag stays set.
//
// Flag semantics per Creation Kit ActorBase template docs (which tab each
// flag inherits): traits covers race/gender/skin/height/weight, character
// gen (head parts) rides Use Traits; inventory covers the default outfit.
// Reference: UESP "Skyrim Mod:Mod File Format/NPC_" + CK wiki "BaseActorData".
// Documented in docs/formats/actors.md.

import Foundation

/// Terminal resolution failures. Per-field fallbacks never throw; only a
/// broken chain (dangling FormID, cycle, unusable list) does.
nonisolated enum ActorResolveError: Error, Equatable {
    /// Base or template FormID matches no NPC_ / LVLN record.
    case missingTarget(FormID, referencedBy: FormID?)
    /// TPLT/LVLN graph revisited a record; chain in visit order.
    case cycle([FormID])
    /// Leveled list with no entries — nothing to place.
    case emptyLeveledList(FormID, referencedBy: FormID?)
}

/// One hop in a resolved template chain, base first.
nonisolated enum ActorChainLink: Equatable {
    case npc(FormID)
    /// A leveled list hop plus the entry the deterministic policy chose.
    case leveled(list: FormID, chosen: FormID)
}

/// An appearance field paired with the NPC_ record that provided it.
nonisolated struct ActorSourcedField<Value: Equatable>: Equatable {
    let value: Value
    let source: FormID
}

/// Appearance-relevant fields of one actor after template resolution.
nonisolated struct ResolvedActorAppearance: Equatable {
    let base: FormID
    let chain: [ActorChainLink]
    let isFemale: ActorSourcedField<Bool>
    let race: ActorSourcedField<FormID?>
    let wornArmor: ActorSourcedField<FormID?>
    let headParts: ActorSourcedField<[FormID]>
    let defaultOutfit: ActorSourcedField<FormID?>
}

/// Resolves template chains against pre-built single-plugin record indexes
/// (raw-FormID keys, matching CellSceneBuilder's convention).
nonisolated struct ActorTemplateResolver {
    let actors: [UInt32: ActorBase]
    let leveledActors: [UInt32: LeveledList]

    /// Indexes every decodable NPC_ + LVLN top-group record. Undecodable
    /// records drop out of the index and later resolve as missing targets.
    static func build(from file: ESMFile, localized: Bool) -> ActorTemplateResolver {
        var actors: [UInt32: ActorBase] = [:]
        if let top = file.topGroup(of: "NPC_"), let children = try? top.children() {
            for case let .record(record) in children {
                guard record.type == "NPC_", !record.isDeleted else { continue }
                actors[record.formID] = try? ActorBase(record: record, localized: localized)
            }
        }
        var leveled: [UInt32: LeveledList] = [:]
        if let top = file.topGroup(of: "LVLN"), let children = try? top.children() {
            for case let .record(record) in children {
                guard record.type == "LVLN", !record.isDeleted else { continue }
                leveled[record.formID] = try? LeveledList(record: record)
            }
        }
        return ActorTemplateResolver(actors: actors, leveledActors: leveled)
    }

    func resolve(base: FormID) throws -> ResolvedActorAppearance {
        let (npcs, chain) = try resolveChain(base: base)
        return ResolvedActorAppearance(
            base: base,
            chain: chain,
            isFemale: resolveField(in: npcs, flag: .useTraits) {
                ActorSourcedField(value: $0.isFemale, source: $0.formID)
            },
            race: resolveField(in: npcs, flag: .useTraits) {
                ActorSourcedField(value: $0.race, source: $0.formID)
            },
            wornArmor: resolveField(in: npcs, flag: .useTraits) {
                ActorSourcedField(value: $0.wornArmor, source: $0.formID)
            },
            headParts: resolveField(in: npcs, flag: .useTraits) {
                ActorSourcedField(value: $0.headParts, source: $0.formID)
            },
            defaultOutfit: resolveField(in: npcs, flag: .useInventory) {
                ActorSourcedField(value: $0.defaultOutfit, source: $0.formID)
            }
        )
    }

    /// Walks TPLT links from `base`, expanding LVLN hops via the
    /// deterministic entry policy, until a record without a template.
    private func resolveChain(
        base: FormID
    ) throws -> (npcs: [ActorBase], chain: [ActorChainLink]) {
        var npcs: [ActorBase] = []
        var chain: [ActorChainLink] = []
        var visited: Set<UInt32> = []
        var visitOrder: [FormID] = []
        var next: FormID? = base
        var referencedBy: FormID?
        while let current = next {
            guard visited.insert(current.rawValue).inserted else {
                throw ActorResolveError.cycle(visitOrder + [current])
            }
            visitOrder.append(current)
            if let npc = actors[current.rawValue] {
                npcs.append(npc)
                chain.append(.npc(current))
                next = npc.template
                referencedBy = current
            } else if let list = leveledActors[current.rawValue] {
                guard let entry = list.deterministicEntry else {
                    throw ActorResolveError.emptyLeveledList(
                        current, referencedBy: referencedBy
                    )
                }
                chain.append(.leveled(list: current, chosen: entry.reference))
                next = entry.reference
                referencedBy = current
            } else {
                throw ActorResolveError.missingTarget(current, referencedBy: referencedBy)
            }
        }
        return (npcs, chain)
    }

    /// A record delegates a field upward only while it has a template and its
    /// governing flag is set; a set flag without a template is inert. The
    /// last chain record always provides the field.
    private func resolveField<Value>(
        in npcs: [ActorBase],
        flag: ActorBase.TemplateFlags,
        _ extract: (ActorBase) -> ActorSourcedField<Value>
    ) -> ActorSourcedField<Value> {
        for (index, npc) in npcs.enumerated() {
            let delegates = npc.template != nil
                && npc.templateFlags.contains(flag)
                && index < npcs.count - 1
            if !delegates {
                return extract(npc)
            }
        }
        // Unreachable for non-empty chains; resolveChain guarantees >= 1 NPC.
        return extract(npcs[npcs.count - 1])
    }
}
