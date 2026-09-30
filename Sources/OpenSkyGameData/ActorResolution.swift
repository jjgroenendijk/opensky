// Actor template-chain resolution: follow NPC_ TPLT links through NPC_ and LVLN
// targets, then resolve each field group to the chain record that provides it,
// driven by the ACBS template flags. A field delegates upward only while its
// flag is set. See docs/engine/actor-resolution.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

/// Terminal resolution failures. Per-field fallbacks never throw; only a
/// broken chain (dangling FormID, cycle, unusable list) does.
nonisolated public enum ActorResolveError: Error, Equatable {
    /// Base or template FormID matches no NPC_ / LVLN record.
    case missingTarget(FormID, referencedBy: FormID?)
    /// TPLT/LVLN graph revisited a record; chain in visit order.
    case cycle([FormID])
    /// Leveled list with no entries — nothing to place.
    case emptyLeveledList(FormID, referencedBy: FormID?)
}

/// One hop in a resolved template chain, base first.
nonisolated public enum ActorChainLink: Equatable, Sendable {
    case npc(FormID)
    /// A leveled list hop plus the entry the deterministic policy chose.
    case leveled(list: FormID, chosen: FormID)
}

/// An appearance field paired with the NPC_ record that provided it.
nonisolated public struct ActorSourcedField<Value: Equatable>: Equatable {
    public let value: Value
    public let source: FormID
}

/// Appearance-relevant fields of one actor after template resolution.
nonisolated public struct ResolvedActorAppearance: Equatable {
    public let base: FormID
    public let chain: [ActorChainLink]
    public let isFemale: ActorSourcedField<Bool>
    public let race: ActorSourcedField<FormID?>
    /// VTCK, inherited through `useTraits` with the other Traits-tab fields.
    public let voiceType: ActorSourcedField<FormID?>
    public let wornArmor: ActorSourcedField<FormID?>
    public let headParts: ActorSourcedField<[FormID]>
    public let defaultOutfit: ActorSourcedField<FormID?>
}

/// Stat-relevant fields of one actor after template resolution. Separate from
/// `ResolvedActorAppearance`: stats follow `useStats` and feed
/// `ActorValueDerivation`. The race is resolved here too, for the starting
/// attributes.
nonisolated public struct ResolvedActorStats: Equatable {
    /// RNAM, resolved through `useTraits` — the Creation Kit puts race on the
    /// Traits tab, not the Stats tab.
    public let race: ActorSourcedField<FormID?>
    /// RNAM of the record that supplies the stats: the race the starting attributes
    /// come from. This differs from `race`, and no source documents it; probing
    /// `Skyrim.esm` against baked DNAM values settles it (`ActorValueRealDataTests`).
    /// Only `ActorValueDerivation` reads this; the renderer uses `race`.
    public let statsRace: ActorSourcedField<FormID?>
    /// ACBS stat words plus CNAM, resolved through `useStats`: "Use stats
    /// (Stats tab, including level, autocalc, skills, health/magicka/stamina,
    /// speed, bleedout, class)" (UESP NPC_ ACBS template data flags).
    public let stats: ActorSourcedField<ActorBase.Stats>
    /// The ACBS auto-calc and PC-level-mult bits, which sit on the Stats tab
    /// and therefore ride `useStats` with the words beside them.
    public let autoCalculatesStats: ActorSourcedField<Bool>
    public let usesPlayerLevelMultiplier: ActorSourcedField<Bool>
}

/// Ordered AI package stack after `useAIPackages` template inheritance.
nonisolated public struct ResolvedActorPackages: Equatable {
    public let packages: ActorSourcedField<[FormID]>
}

/// Authored spell list after `useSpellList` template inheritance. Its own struct,
/// because it follows its own ACBS bit and feeds the spellbook.
nonisolated public struct ResolvedActorSpells: Equatable {
    /// SPLO, resolved through `useSpellList`.
    public let spells: ActorSourcedField<[FormID]>
    /// PRKR, resolved through the same flag: UESP names it "Use spelllist (both
    /// spells and perks)".
    public let perks: ActorSourcedField<[FormID]>
    /// RNAM, resolved through `useTraits` — the race whose own `SPLO` run every
    /// member of it carries.
    public let race: ActorSourcedField<FormID?>
}

/// Faction memberships and AI attributes after template inheritance. SNAM follows
/// its own ACBS bit. AIDT rides along on its own flag, because hostility reads
/// memberships and aggression together.
nonisolated public struct ResolvedActorFactions: Equatable {
    /// SNAM, resolved through `useFactions`.
    public let factions: ActorSourcedField<[ActorBase.FactionMembership]>
    /// AIDT, resolved through `useAIData` — the flag UESP names "Use AI Data
    /// (AI Data tab, including aggression, confidence, morality, combat style
    /// and gift filter)". Nil when the providing record authors none.
    public let aiData: ActorSourcedField<ActorAIData?>
    /// CRIF, resolved through `useFactions` beside SNAM: the Creation Kit shows the
    /// crime faction on the Factions tab.
    public var crimeFaction: FormID? {
        crimeFactionField.value
    }

    public let crimeFactionField: ActorSourcedField<FormID?>
}

/// Resolves template chains against pre-built single-plugin record indexes
/// (raw-FormID keys, matching CellSceneBuilder's convention).
nonisolated public struct ActorTemplateResolver: Sendable {
    public let actors: [UInt32: ActorBase]
    public let leveledActors: [UInt32: LeveledList]
    /// LVSP decodes by raw FormID. An actor's `SPLO` run can name leveled spell lists,
    /// so the spell baseline must expand them. Defaulted, so older fixtures still
    /// build.
    public let leveledSpells: [UInt32: LeveledList]

    public init(
        actors: [UInt32: ActorBase],
        leveledActors: [UInt32: LeveledList],
        leveledSpells: [UInt32: LeveledList] = [:]
    ) {
        self.actors = actors
        self.leveledActors = leveledActors
        self.leveledSpells = leveledSpells
    }

    /// Indexes every decodable NPC_ + LVLN top-group record. Undecodable
    /// records drop out of the index and later resolve as missing targets.
    public static func build(from file: ESMFile, localized: Bool) -> ActorTemplateResolver {
        var actors: [UInt32: ActorBase] = [:]
        if let top = file.topGroup(of: "NPC_"), let children = try? top.children() {
            for case let .record(record) in children {
                guard record.type == "NPC_", !record.isDeleted else { continue }
                actors[record.formID] = try? ActorBase(record: record, localized: localized)
            }
        }
        return ActorTemplateResolver(
            actors: actors,
            leveledActors: leveledLists(in: file, of: "LVLN"),
            leveledSpells: leveledLists(in: file, of: "LVSP")
        )
    }

    /// Every decodable leveled list of one record type, by raw FormID.
    private static func leveledLists(
        in file: ESMFile,
        of type: FourCC
    ) -> [UInt32: LeveledList] {
        var lists: [UInt32: LeveledList] = [:]
        guard let top = file.topGroup(of: type), let children = try? top.children() else {
            return lists
        }
        for case let .record(record) in children {
            guard record.type == type, !record.isDeleted else { continue }
            lists[record.formID] = try? LeveledList(record: record)
        }
        return lists
    }

    public func resolve(base: FormID) throws -> ResolvedActorAppearance {
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
            voiceType: resolveField(in: npcs, flag: .useTraits) {
                ActorSourcedField(value: $0.voiceType, source: $0.formID)
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

    /// The same chain walk as `resolve(base:)`, resolving the stat fields instead of
    /// the appearance fields.
    public func resolveStats(base: FormID) throws -> ResolvedActorStats {
        let (npcs, _) = try resolveChain(base: base)
        return ResolvedActorStats(
            race: resolveField(in: npcs, flag: .useTraits) {
                ActorSourcedField(value: $0.race, source: $0.formID)
            },
            statsRace: resolveField(in: npcs, flag: .useStats) {
                ActorSourcedField(value: $0.race, source: $0.formID)
            },
            stats: resolveField(in: npcs, flag: .useStats) {
                ActorSourcedField(value: $0.stats, source: $0.formID)
            },
            autoCalculatesStats: resolveField(in: npcs, flag: .useStats) {
                ActorSourcedField(value: $0.autoCalculatesStats, source: $0.formID)
            },
            usesPlayerLevelMultiplier: resolveField(in: npcs, flag: .useStats) {
                ActorSourcedField(value: $0.flags.contains(.pcLevelMult), source: $0.formID)
            }
        )
    }

    /// Resolves only the package-list field group. A local empty list remains
    /// authoritative unless `useAIPackages` explicitly delegates it.
    public func resolvePackages(base: FormID) throws -> ResolvedActorPackages {
        let (npcs, _) = try resolveChain(base: base)
        return ResolvedActorPackages(
            packages: resolveField(in: npcs, flag: .useAIPackages) {
                ActorSourcedField(value: $0.packages, source: $0.formID)
            }
        )
    }

    /// Resolves only the spell-list field group. A local empty list stays
    /// authoritative unless `useSpellList` delegates it.
    public func resolveSpells(base: FormID) throws -> ResolvedActorSpells {
        let (npcs, _) = try resolveChain(base: base)
        return ResolvedActorSpells(
            spells: resolveField(in: npcs, flag: .useSpellList) {
                ActorSourcedField(value: $0.spells, source: $0.formID)
            },
            perks: resolveField(in: npcs, flag: .useSpellList) {
                ActorSourcedField(value: $0.perks, source: $0.formID)
            },
            race: resolveField(in: npcs, flag: .useTraits) {
                ActorSourcedField(value: $0.race, source: $0.formID)
            }
        )
    }

    /// Resolves the faction-membership field group and the AI attributes beside it.
    /// A local empty list stays authoritative unless `useFactions` delegates it; the
    /// AIDT delegates on `useAIData`.
    public func resolveFactions(base: FormID) throws -> ResolvedActorFactions {
        let (npcs, _) = try resolveChain(base: base)
        return ResolvedActorFactions(
            factions: resolveField(in: npcs, flag: .useFactions) {
                ActorSourcedField(value: $0.factions, source: $0.formID)
            },
            aiData: resolveField(in: npcs, flag: .useAIData) {
                ActorSourcedField(value: $0.aiData, source: $0.formID)
            },
            crimeFactionField: resolveField(in: npcs, flag: .useFactions) {
                ActorSourcedField(value: $0.crimeFaction, source: $0.formID)
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
