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
    /// VTCK, inherited through `useTraits` with the other Traits-tab fields.
    let voiceType: ActorSourcedField<FormID?>
    let wornArmor: ActorSourcedField<FormID?>
    let headParts: ActorSourcedField<[FormID]>
    let defaultOutfit: ActorSourcedField<FormID?>
}

/// Stat-relevant fields of one actor after template resolution (issue #194).
///
/// A sibling of `ResolvedActorAppearance` rather than more fields on it,
/// because the two answer to different template flags and have different
/// consumers: appearance rides `useTraits` and feeds the renderer, stats ride
/// `useStats` and feed `ActorValueDerivation`. The race is resolved here too,
/// through `useTraits` exactly as the appearance resolves it, because the
/// starting attributes come from the race and the derivation would otherwise
/// have to reach back into the appearance for one field.
nonisolated struct ResolvedActorStats: Equatable {
    let base: FormID
    let chain: [ActorChainLink]
    /// RNAM, resolved through `useTraits` — the Creation Kit puts race on the
    /// Traits tab, not the Stats tab.
    let race: ActorSourcedField<FormID?>
    /// RNAM of the record that supplies the stats, which is the race the
    /// *starting attributes* come from.
    ///
    /// Not the same field as `race`, and the difference is observed rather than
    /// documented anywhere. Neither UESP nor the Creation Kit wiki says which
    /// race feeds the base attributes when `useTraits` and `useStats` resolve to
    /// different records; the wiki only says base health is "determined by their
    /// Race, Class, and Level" (<https://ck.uesp.net/wiki/Stats_Tab>). Probing
    /// `Skyrim.esm` settles it: with the traits race, 61 of 4297 auto-calc
    /// records disagree with the values the editor itself baked into their DNAM;
    /// with the stats record's race, 26 do, and every remaining one is the same
    /// stale template (see `ActorValueRealDataTests`). The skeleton, draugr and
    /// creature records that flip are exactly the ones whose traits and stats
    /// resolve to different races.
    ///
    /// The renderer still skins an actor with `race`. This field only feeds
    /// `ActorValueDerivation`.
    let statsRace: ActorSourcedField<FormID?>
    /// ACBS stat words plus CNAM, resolved through `useStats`: "Use stats
    /// (Stats tab, including level, autocalc, skills, health/magicka/stamina,
    /// speed, bleedout, class)" (UESP NPC_ ACBS template data flags).
    let stats: ActorSourcedField<ActorBase.Stats>
    /// The ACBS auto-calc and PC-level-mult bits, which sit on the Stats tab
    /// and therefore ride `useStats` with the words beside them.
    let autoCalculatesStats: ActorSourcedField<Bool>
    let usesPlayerLevelMultiplier: ActorSourcedField<Bool>
}

/// Ordered AI package stack after `useAIPackages` template inheritance.
nonisolated struct ResolvedActorPackages: Equatable {
    let base: FormID
    let chain: [ActorChainLink]
    let packages: ActorSourcedField<[FormID]>
}

/// Authored spell list after `useSpellList` template inheritance (issue #473).
///
/// A sibling of `ResolvedActorPackages` rather than more fields on the
/// appearance or the stats, for the reason those two are separate: the list
/// answers to its own ACBS template-data bit, and its consumer is the spellbook
/// rather than the renderer or the actor-value derivation.
nonisolated struct ResolvedActorSpells: Equatable {
    let base: FormID
    let chain: [ActorChainLink]
    /// SPLO, resolved through `useSpellList`.
    let spells: ActorSourcedField<[FormID]>
    /// PRKR, resolved through the same flag: UESP names it "Use spelllist
    /// (both spells and perks)", so an actor delegating its spell list
    /// delegates its perk list with it (issue #497).
    let perks: ActorSourcedField<[FormID]>
    /// RNAM, resolved through `useTraits` — the race whose own `SPLO` run every
    /// member of it carries.
    let race: ActorSourcedField<FormID?>
}

/// Faction memberships and AI attributes after template inheritance
/// (issues #501 and #503).
///
/// Its own struct for the reason the spell list has one: the SNAM run answers
/// to its own ACBS template-data bit, and its consumers — hostility, crime
/// response and vendor rules — are none of the ones already resolved here.
///
/// The AIDT rides along on its own flag rather than getting a struct of its
/// own, the way `ResolvedActorSpells` carries the perk run beside the spell
/// run: the hostility derivation reads the memberships and the aggression
/// together, and two walks of the same template chain would only be a second
/// chance for the two answers to disagree.
nonisolated struct ResolvedActorFactions: Equatable {
    let base: FormID
    let chain: [ActorChainLink]
    /// SNAM, resolved through `useFactions`.
    let factions: ActorSourcedField<[ActorBase.FactionMembership]>
    /// AIDT, resolved through `useAIData` — the flag UESP names "Use AI Data
    /// (AI Data tab, including aggression, confidence, morality, combat style
    /// and gift filter)". Nil when the providing record authors none.
    let aiData: ActorSourcedField<ActorAIData?>
}

/// Resolves template chains against pre-built single-plugin record indexes
/// (raw-FormID keys, matching CellSceneBuilder's convention).
nonisolated struct ActorTemplateResolver {
    let actors: [UInt32: ActorBase]
    let leveledActors: [UInt32: LeveledList]
    /// LVSP decodes by raw FormID (issue #473). An actor's `SPLO` run names
    /// leveled *spell* lists as freely as it names SPEL records — every vanilla
    /// caster's offensive spells arrive that way, observed against
    /// `Skyrim.esm` — so the spell baseline has to be able to expand one.
    ///
    /// Defaulted, so the fixtures that build a resolver by hand for the
    /// appearance and package paths are untouched by a field they do not use.
    let leveledSpells: [UInt32: LeveledList]

    init(
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
    static func build(from file: ESMFile, localized: Bool) -> ActorTemplateResolver {
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

    /// The same chain walk as `resolve(base:)`, resolving the stat fields
    /// instead of the appearance fields (issue #194).
    func resolveStats(base: FormID) throws -> ResolvedActorStats {
        let (npcs, chain) = try resolveChain(base: base)
        return ResolvedActorStats(
            base: base,
            chain: chain,
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
    func resolvePackages(base: FormID) throws -> ResolvedActorPackages {
        let (npcs, chain) = try resolveChain(base: base)
        return ResolvedActorPackages(
            base: base,
            chain: chain,
            packages: resolveField(in: npcs, flag: .useAIPackages) {
                ActorSourcedField(value: $0.packages, source: $0.formID)
            }
        )
    }

    /// Resolves only the spell-list field group (issue #473). A local empty
    /// list stays authoritative unless `useSpellList` delegates it, which is
    /// the rule every other field group here follows.
    func resolveSpells(base: FormID) throws -> ResolvedActorSpells {
        let (npcs, chain) = try resolveChain(base: base)
        return ResolvedActorSpells(
            base: base,
            chain: chain,
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

    /// Resolves the faction-membership field group and the AI attributes
    /// beside it (issues #501 and #503). A local empty list stays authoritative
    /// unless `useFactions` delegates it, the rule every other field group here
    /// follows, and the AIDT delegates on its own `useAIData` flag.
    func resolveFactions(base: FormID) throws -> ResolvedActorFactions {
        let (npcs, chain) = try resolveChain(base: base)
        return ResolvedActorFactions(
            base: base,
            chain: chain,
            factions: resolveField(in: npcs, flag: .useFactions) {
                ActorSourcedField(value: $0.factions, source: $0.formID)
            },
            aiData: resolveField(in: npcs, flag: .useAIData) {
                ActorSourcedField(value: $0.aiData, source: $0.formID)
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
