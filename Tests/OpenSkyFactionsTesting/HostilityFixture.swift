// Synthetic factions, relationships, and actors for the hostility suites. One
// plugin holds all three record types so FACT and RELA resolve to the same
// `ReferenceKey`s.

import FormatsESMTesting
import Foundation
@testable import OpenSkyActorsInterface
@testable import OpenSkyFactionsInterface
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData

public enum HostilityFixture {
    public static let pluginName = "Base.esm"

    /// FormIDs the suites name. Factions low, actor bases high, so a mistaken
    /// swap of the two shows up as an unresolved link rather than as a wrong
    /// answer.
    public enum Factions {
        public static let bandit: UInt32 = 0x10
        public static let guards: UInt32 = 0x11
        public static let player: UInt32 = 0x12
        public static let town: UInt32 = 0x13
    }

    public enum Actors {
        public static let bandit: UInt32 = 0x600
        public static let cityGuard: UInt32 = 0x601
        public static let townsfolk: UInt32 = 0x602
    }

    /// One authored XNAM, from one faction toward another.
    public struct Relation {
        public let from: UInt32
        public let to: UInt32
        public let reaction: UInt32

        public init(_ from: UInt32, _ to: UInt32, _ reaction: Faction.CombatReaction) {
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
    public struct Pair {
        public let parent: UInt32
        public let child: UInt32
        public let rank: UInt16

        public init(_ parent: UInt32, _ child: UInt32, _ rank: RelationshipRank) {
            self.parent = parent
            self.child = child
            self.rank = rank.rawValue
        }
    }

    public static func key(_ objectID: UInt32) -> ReferenceKey {
        .plugin(name: pluginName.lowercased(), objectID: objectID)
    }

    public static func id(_ objectID: UInt32) -> ResolvedFormID {
        ResolvedFormID(plugin: pluginName, objectID: objectID)
    }

    /// A load order carrying the four named factions, the relations given, and
    /// the relationship records given.
    public static func file(
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

    public static func factionStore(relations: [Relation] = []) throws -> FactionStore {
        try FactionStore(plugins: [(pluginName, file(relations: relations))])
    }

    /// One actor as the derivation reads it.
    public static func profile(
        actor: UInt32,
        memberships: [(faction: UInt32, rank: Int8)] = [],
        relationships: [(other: ReferenceKey, rank: Int8)] = [],
        aggression: ActorAggression = .aggressive,
        hostilityOverride: ActorHostility? = nil,
        key overrideKey: ReferenceKey? = nil
    ) -> ActorSocialProfile {
        ActorSocialProfile(
            key: overrideKey ?? key(actor),
            base: id(actor),
            memberships: ActorFactionState(memberships: memberships.map {
                ActorFactionMembership(faction: key($0.faction), rank: $0.rank)
            }),
            relationshipOverrides: relationshipState(relationships),
            aiData: aiData(aggression: aggression),
            hostilityOverride: hostilityOverride
        )
    }

    /// A scripted relationship component, as `SetRelationshipRank` writes it.
    public static func relationshipState(
        _ entries: [(other: ReferenceKey, rank: Int8)]
    ) -> ActorRelationshipState {
        ActorRelationshipState(overrides: entries.map {
            ActorRelationshipOverride(other: $0.other, rank: $0.rank)
        })
    }

    /// The player as the derivation reads them: no base record, no authored
    /// memberships, and no aggression of their own.
    public static func player(
        memberships: [(faction: UInt32, rank: Int8)] = [],
        relationships: [(other: ReferenceKey, rank: Int8)] = [],
        key overrideKey: ReferenceKey = .player
    ) -> ActorSocialProfile {
        ActorSocialProfile(
            key: overrideKey,
            base: nil,
            memberships: ActorFactionState(memberships: memberships.map {
                ActorFactionMembership(faction: key($0.faction), rank: $0.rank)
            }),
            relationshipOverrides: relationshipState(relationships),
            aiData: .absent,
            hostilityOverride: nil
        )
    }

    public static func aiData(aggression: ActorAggression) -> ActorAIData {
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
