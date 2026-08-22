// Synthetic factions, relationships and actors for the hostility-derivation
// suites (issue #503). Every layout comes from `FactionFixture` and
// `RelationshipFixture`, so no bytes from the game install appear here
// (AGENTS.md "Legal & IP boundary").
//
// One plugin carries all three record types, because the derivation joins them:
// a FACT relation and a RELA record have to resolve to the same
// `ReferenceKey`s or the suites would be testing the fixture rather than the
// derivation.

import Foundation
@testable import opensky

enum HostilityFixture {
    static let pluginName = "Base.esm"

    /// FormIDs the suites name. Factions low, actor bases high, so a mistaken
    /// swap of the two shows up as an unresolved link rather than as a wrong
    /// answer.
    enum Factions {
        static let bandit: UInt32 = 0x10
        static let guards: UInt32 = 0x11
        static let player: UInt32 = 0x12
        static let town: UInt32 = 0x13
    }

    enum Actors {
        static let bandit: UInt32 = 0x600
        static let cityGuard: UInt32 = 0x601
        static let townsfolk: UInt32 = 0x602
    }

    /// One authored XNAM, from one faction toward another.
    struct Relation {
        let from: UInt32
        let to: UInt32
        let reaction: UInt32

        init(_ from: UInt32, _ to: UInt32, _ reaction: Faction.CombatReaction) {
            self.from = from
            self.to = to
            self.reaction = Self.raw(reaction)
        }

        private static func raw(_ reaction: Faction.CombatReaction) -> UInt32 {
            switch reaction {
            case .neutral: 0
            case .enemy: 1
            case .ally: 2
            case .friend: 3
            case let .unknown(raw): raw
            }
        }
    }

    /// One authored RELA, parent toward child.
    struct Pair {
        let parent: UInt32
        let child: UInt32
        let rank: UInt16

        init(_ parent: UInt32, _ child: UInt32, _ rank: RelationshipRank) {
            self.parent = parent
            self.child = child
            self.rank = rank.rawValue
        }
    }

    static func key(_ objectID: UInt32) -> ReferenceKey {
        .plugin(name: pluginName.lowercased(), objectID: objectID)
    }

    static func id(_ objectID: UInt32) -> ResolvedFormID {
        ResolvedFormID(plugin: pluginName, objectID: objectID)
    }

    /// A load order carrying the four named factions, the relations given, and
    /// the relationship records given.
    static func file(
        relations: [Relation] = [],
        pairs: [Pair] = []
    ) throws -> ESMFile {
        let ids = [Factions.bandit, Factions.guards, Factions.player, Factions.town]
        let names = ["BanditFaction", "GuardFaction", "PlayerFaction", "TownFaction"]
        let factions = zip(ids, names).map { formID, editorID in
            FactionFixture.record(
                formID: formID,
                editorID: editorID,
                body: relations
                    .filter { $0.from == formID }
                    .reduce(Data()) {
                        $0 + FactionFixture.relation($1.to, modifier: 0, reaction: $1.reaction)
                    }
            )
        }
        var data = ESMFixture.tes4()
        data += ESMFixture.topGroup("FACT", contents: factions.reduce(Data(), +))
        if !pairs.isEmpty {
            let records = pairs.enumerated().map { offset, pair in
                RelationshipFixture.record(
                    formID: UInt32(0x900 + offset),
                    editorID: "Rela\(offset)",
                    body: RelationshipFixture.data(
                        parent: pair.parent, child: pair.child, rank: pair.rank
                    )
                )
            }
            data += ESMFixture.topGroup("RELA", contents: records.reduce(Data(), +))
        }
        return try ESMFile(data: data)
    }

    /// The derivation over one such load order.
    static func derivation(
        relations: [Relation] = [],
        pairs: [Pair] = []
    ) throws -> HostilityDerivation {
        let file = try file(relations: relations, pairs: pairs)
        return HostilityDerivation(
            relations: FactionRelationIndex(
                store: FactionStore(plugins: [(pluginName, file)])
            ),
            relationships: RelationshipStore(plugins: [(pluginName, file)])
        )
    }

    static func factionStore(relations: [Relation] = []) throws -> FactionStore {
        try FactionStore(plugins: [(pluginName, file(relations: relations))])
    }

    /// One actor as the derivation reads it.
    static func profile(
        actor: UInt32,
        memberships: [(faction: UInt32, rank: Int8)] = [],
        aggression: ActorAggression = .aggressive,
        hostilityOverride: ActorHostility? = nil
    ) -> ActorSocialProfile {
        ActorSocialProfile(
            key: key(actor),
            base: id(actor),
            memberships: ActorFactionState(memberships: memberships.map {
                ActorFactionMembership(faction: key($0.faction), rank: $0.rank)
            }),
            aiData: aiData(aggression: aggression),
            hostilityOverride: hostilityOverride
        )
    }

    /// The player as the derivation reads them: no base record, no authored
    /// memberships, and no aggression of their own.
    static func player(
        memberships: [(faction: UInt32, rank: Int8)] = []
    ) -> ActorSocialProfile {
        ActorSocialProfile(
            key: .player,
            base: nil,
            memberships: ActorFactionState(memberships: memberships.map {
                ActorFactionMembership(faction: key($0.faction), rank: $0.rank)
            }),
            aiData: .absent,
            hostilityOverride: nil
        )
    }

    static func aiData(aggression: ActorAggression) -> ActorAIData {
        ActorAIData(
            aggression: aggression,
            confidence: .average,
            energy: 50,
            morality: .anyCrime,
            mood: 0,
            assistance: .helpsFriendsAndAllies,
            usesAggroRadiusBehavior: false,
            unknown: 0,
            warnDistance: nil,
            warnOrAttackDistance: nil,
            attackDistance: nil
        )
    }
}
