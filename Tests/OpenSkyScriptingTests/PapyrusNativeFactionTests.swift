// The faction and relationship natives: `Actor` membership, the relationship
// accessors, the pair reads, and the refusal a script must tell apart from
// "not a member". Mutations go through `FactionRuntime` or
// `RelationshipRuntime` into the world-state store, so they save like seeds.

import FormatsESMTesting
import Foundation
@testable import OpenSkyFactions
@testable import OpenSkyFactionsInterface
import OpenSkyFactionsTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkyScriptingTesting
@testable import OpenSkyWorldState
import Testing

@MainActor
struct PapyrusNativeFactionTests {
    private typealias Social = HostilityFixture

    // MARK: - Memberships

    /// "Adds the Actor to a specified faction at rank 0."
    /// (<https://ck.uesp.net/wiki/AddToFaction_-_Actor>)
    @Test func addToFactionJoinsAtRankZeroAndIsInFactionSeesIt() throws {
        let fixture = try Self.fixture()
        let guards = try handle(fixture, faction: Self.guards)

        call("Actor", "AddToFaction", fixture, receiver: fixture.actor, arguments: [
            .object(guards)
        ])

        #expect(fixture.factions.rank(of: fixture.actorKey, in: Self.guards) == 0)
        let member = call(
            "Actor", "IsInFaction", fixture,
            receiver: fixture.actor,
            arguments: [.object(guards)],
            returnType: .boolean
        )
        #expect(member == .returned(.boolean(true)))
    }

    /// "If the Actor is already in the faction, this function does nothing." —
    /// so a second add must not demote a promoted member back to rank 0.
    @Test func addToFactionDoesNotDemoteAnExistingMember() throws {
        let fixture = try Self.fixture()
        let guards = try handle(fixture, faction: Self.guards)
        fixture.factions.join(fixture.actorKey, to: Self.guards, rank: 3)

        call("Actor", "AddToFaction", fixture, receiver: fixture.actor, arguments: [
            .object(guards)
        ])

        #expect(fixture.factions.rank(of: fixture.actorKey, in: Self.guards) == 3)
    }

    /// "Removes this actor from the specified faction."
    /// (<https://ck.uesp.net/wiki/RemoveFromFaction_-_Actor>)
    @Test func removeFromFactionClearsTheMembership() throws {
        let fixture = try Self.fixture()
        let guards = try handle(fixture, faction: Self.guards)
        fixture.factions.join(fixture.actorKey, to: Self.guards, rank: 2)

        call("Actor", "RemoveFromFaction", fixture, receiver: fixture.actor, arguments: [
            .object(guards)
        ])

        #expect(fixture.factions.rank(of: fixture.actorKey, in: Self.guards) == nil)
    }

    /// "-2 if the Actor is not in the faction. -1 if the Actor is in the faction,
    /// with a rank set to -1."
    /// (<https://ck.uesp.net/wiki/GetFactionRank_-_Actor>) The two have to stay
    /// distinguishable, which is the whole reason the native answers -2 rather
    /// than the -1 its console twin answers.
    @Test func getFactionRankSeparatesANonMemberFromARankOfMinusOne() throws {
        let fixture = try Self.fixture()
        let guards = try handle(fixture, faction: Self.guards)

        #expect(rank(fixture, guards) == .returned(.integer(-2)))
        fixture.factions.join(fixture.actorKey, to: Self.guards, rank: -1)
        #expect(rank(fixture, guards) == .returned(.integer(-1)))
        fixture.factions.join(fixture.actorKey, to: Self.guards, rank: 0)
        #expect(rank(fixture, guards) == .returned(.integer(0)))
    }

    /// "Sets this actor's rank in the specified faction. Adds the actor to the
    /// faction if necessary."
    /// (<https://ck.uesp.net/wiki/SetFactionRank_-_Actor>)
    @Test func setFactionRankAddsAndPromotes() throws {
        let fixture = try Self.fixture()
        let guards = try handle(fixture, faction: Self.guards)

        call("Actor", "SetFactionRank", fixture, receiver: fixture.actor, arguments: [
            .object(guards), .integer(4)
        ])
        #expect(fixture.factions.rank(of: fixture.actorKey, in: Self.guards) == 4)

        call("Actor", "SetFactionRank", fixture, receiver: fixture.actor, arguments: [
            .object(guards), .integer(1)
        ])
        #expect(fixture.factions.rank(of: fixture.actorKey, in: Self.guards) == 1)
    }

    /// "Valid range is -128 to 127" — the `SNAM` rank byte. A rank outside it is
    /// refused rather than wrapped into a rank the script did not ask for.
    @Test func setFactionRankRefusesARankOutsideTheByte() throws {
        let fixture = try Self.fixture()
        let guards = try handle(fixture, faction: Self.guards)

        let result = call("Actor", "SetFactionRank", fixture, receiver: fixture.actor, arguments: [
            .object(guards), .integer(500)
        ])

        #expect(isFailure(result))
        #expect(fixture.factions.rank(of: fixture.actorKey, in: Self.guards) == nil)
    }

    // MARK: - Relationships

    /// The record layer: a `RELA` between the two bases answers in either
    /// direction, over the "4: Lover ... -4: Archnemesis" table
    /// (<https://ck.uesp.net/wiki/GetRelationshipRank_-_Actor>).
    @Test func getRelationshipRankReadsTheRecord() throws {
        let fixture = try Self.fixture(
            pairs: [Social.Pair(Social.Actors.cityGuard, Social.Actors.bandit, .foe)]
        )

        #expect(relationship(fixture) == .returned(.integer(-2)))
    }

    /// The override layer: what a script set wins, and both actors can answer it
    /// because both components are written.
    @Test func setRelationshipRankIsReadBackFromEitherSide() throws {
        let fixture = try Self.fixture(
            pairs: [Social.Pair(Social.Actors.cityGuard, Social.Actors.bandit, .foe)]
        )

        call("Actor", "SetRelationshipRank", fixture, receiver: fixture.actor, arguments: [
            .object(fixture.other), .integer(4)
        ])

        #expect(relationship(fixture) == .returned(.integer(4)))
        #expect(relationship(fixture, reversed: true) == .returned(.integer(4)))
        #expect(
            fixture.relationships.storedRank(
                of: fixture.otherKey, toward: fixture.actorKey
            ) == 4
        )
    }

    /// The wiki lists -4...4 as the acceptable ranks, and the read side maps
    /// through a table that names only those nine — so a value outside it is
    /// refused rather than stored.
    @Test func setRelationshipRankRefusesARankOutsideTheTable() throws {
        let fixture = try Self.fixture()

        let result = call(
            "Actor", "SetRelationshipRank", fixture,
            receiver: fixture.actor,
            arguments: [.object(fixture.other), .integer(9)]
        )

        #expect(isFailure(result))
        #expect(fixture.relationships.state(of: fixture.actorKey).isEmpty)
    }

    /// A pair nothing names is a refusal rather than 0, because 0 is
    /// Acquaintance and a script comparing `>= 1` would read silence as a rank.
    @Test func getRelationshipRankRefusesAnUnnamedPair() throws {
        #expect(try isFailure(relationship(Self.fixture())))
    }

    // MARK: - Pair reads

    /// "0: Neutral, 1: Enemy, 2: Ally, 3: Friend"
    /// (<https://ck.uesp.net/wiki/GetFactionReaction_-_Actor>)
    @Test func getFactionReactionUsesTheCreationKitNumbering() throws {
        let fixture = try Self.fixture(relations: [
            Social.Relation(Social.Factions.guards, Social.Factions.bandit, .enemy)
        ])
        fixture.factions.join(fixture.actorKey, to: Self.guards, rank: 0)
        fixture.factions.join(fixture.otherKey, to: Self.bandits, rank: 0)

        let result = call(
            "Actor", "GetFactionReaction", fixture,
            receiver: fixture.actor,
            arguments: [.object(fixture.other)],
            returnType: .integer
        )

        #expect(result == .returned(.integer(1)))
    }

    /// No wiki page exists for `IsHostileToActor`; the install's own `Actor.pex`
    /// declares `bool IsHostileToActor(Actor akActor) native` and says nothing
    /// about the answer, so it is the derivation's. An Aggressive actor "will
    /// attack Enemies on sight" and nobody else, so an enemy relation between
    /// the two actors' factions is hostility and no relation at all — which
    /// derives as Neutral — is not.
    @Test func isHostileToActorFollowsTheDerivation() throws {
        let hostile = try Self.fixture(relations: [
            Social.Relation(Social.Factions.guards, Social.Factions.bandit, .enemy)
        ])
        hostile.factions.join(hostile.actorKey, to: Self.guards, rank: 0)
        hostile.factions.join(hostile.otherKey, to: Self.bandits, rank: 0)
        let calm = try Self.fixture()

        #expect(isHostileCall(hostile) == .returned(.boolean(true)))
        #expect(isHostileCall(calm) == .returned(.boolean(false)))
    }

    /// "Gets this faction's reaction towards the other faction."
    /// (<https://ck.uesp.net/wiki/Faction_Script>) The receiver is the FACT
    /// itself, which this engine addresses by the same key its memberships are
    /// keyed by.
    @Test func factionGetReactionReadsTheInterfactionTable() throws {
        let fixture = try Self.fixture(relations: [
            Social.Relation(Social.Factions.guards, Social.Factions.bandit, .friend)
        ])

        let result = try call(
            "Faction", "GetReaction", fixture,
            receiver: handle(fixture, faction: Self.guards),
            arguments: [.object(handle(fixture, faction: Self.bandits))],
            returnType: .integer
        )

        #expect(result == .returned(.integer(3)))
    }

    /// Two factions that say nothing about each other are a refusal rather than
    /// Neutral: the `Faction` script's numbering has no value for "unrelated",
    /// and answering Neutral would hide an authored Neutral behind silence.
    @Test func factionGetReactionRefusesAnUnrelatedPair() throws {
        let fixture = try Self.fixture()

        let result = try call(
            "Faction", "GetReaction", fixture,
            receiver: handle(fixture, faction: Self.guards),
            arguments: [.object(handle(fixture, faction: Self.bandits))],
            returnType: .integer
        )

        #expect(isFailure(result))
    }

    // MARK: - Refusals

    /// A session with no faction runtime refuses every membership native rather
    /// than reporting "not a member", which is a fact about the actor and not
    /// about the session.
    @Test func aSessionWithNoFactionRuntimeRefuses() throws {
        let fixture = try Self.fixture(wireRuntimes: false)
        let guards = try handle(fixture, faction: Self.guards)

        for name in ["AddToFaction", "RemoveFromFaction", "IsInFaction", "GetFactionRank"] {
            let result = call(
                "Actor", name, fixture,
                receiver: fixture.actor,
                arguments: [.object(guards)],
                returnType: .integer
            )
            #expect(isFailure(result), "\(name) should refuse without a faction runtime")
        }
    }

    /// A membership native with no `Faction` argument refuses rather than
    /// operating on whatever the first argument happened to be.
    @Test func aMissingFactionArgumentRefuses() throws {
        let fixture = try Self.fixture()

        #expect(isFailure(call(
            "Actor", "IsInFaction", fixture, receiver: fixture.actor, returnType: .boolean
        )))
    }
}

/// The fixture and the call helpers, in an extension so the suite's `@Test`
/// bodies stay inside the strict type-length cap.
@MainActor
extension PapyrusNativeFactionTests {
    /// Two scripted actors plus a faction runtime wired into the bridge the way
    /// `GameViewControllerFactions.wireFactionNatives` wires the session's.
    struct Fixture {
        let session: PapyrusWorldFixture.Session
        let registry: PapyrusNativeRegistry
        let actor: PapyrusObjectHandle
        let actorKey: ReferenceKey
        let other: PapyrusObjectHandle
        let otherKey: ReferenceKey
        let factions: FactionRuntime
        let relationships: RelationshipRuntime
    }

    private static let guards = Social.key(Social.Factions.guards)
    private static let bandits = Social.key(Social.Factions.bandit)

    private static func fixture(
        wireRuntimes: Bool = true,
        relations: [Social.Relation] = [],
        pairs: [Social.Pair] = []
    ) throws -> Fixture {
        let first = try PapyrusWorldFixture.actorEntry(
            objectID: 0x0004_0001,
            base: 0x0004_0002,
            scripts: [VMADFixture.Script("Resident", properties: [])]
        )
        let second = try PapyrusWorldFixture.actorEntry(
            objectID: 0x0004_0003,
            base: 0x0004_0004,
            scripts: [VMADFixture.Script("Resident", properties: [])]
        )
        let session = PapyrusWorldFixture.session(
            objects: [PapyrusWorldFixture.eventScript("Resident", events: [])],
            entries: [first, second]
        )
        PapyrusWorldFixture.drain(session.world)
        let file = try Social.file(relations: relations, pairs: pairs)
        let store = FactionStore(plugins: [(Social.pluginName, file)])
        let relationshipStore = RelationshipStore(plugins: [(Social.pluginName, file)])
        let factions = FactionRuntime(
            store: session.worldState,
            factions: store,
            derivation: HostilityDerivation(
                relations: FactionRelationIndex(store: store),
                relationships: relationshipStore
            )
        )
        let relationships = RelationshipRuntime(
            store: session.worldState, relationships: relationshipStore
        )
        let bases: [ReferenceKey: ResolvedFormID] = [
            first.key: Social.id(Social.Actors.cityGuard),
            second.key: Social.id(Social.Actors.bandit)
        ]
        if wireRuntimes {
            wire(
                session: session,
                factions: factions,
                relationships: relationships,
                bases: bases
            )
        }
        return try Fixture(
            session: session,
            registry: PapyrusWorldFixture.registry(for: session),
            actor: #require(session.bridge.objectHandle(for: first.key)),
            actorKey: first.key,
            other: #require(session.bridge.objectHandle(for: second.key)),
            otherKey: second.key,
            factions: factions,
            relationships: relationships
        )
    }

    /// The five closures the controller installs, with the derivation reading
    /// live components so a native's write is visible to the next read.
    private static func wire(
        session: PapyrusWorldFixture.Session,
        factions: FactionRuntime,
        relationships: RelationshipRuntime,
        bases: [ReferenceKey: ResolvedFormID]
    ) {
        session.bridge.factionRuntime = { _ in factions }
        session.bridge.relationshipRuntime = { relationships }
        session.bridge.actorSocialBase = { bases[$0] }
        session.bridge.factionRelationIndex = { factions.derivation.relations }
        session.bridge.socialDecision = { observer, target in
            let profiles = [observer, target].map { key in
                ActorSocialProfile(
                    key: key,
                    base: bases[key],
                    memberships: factions.state(of: key),
                    relationshipOverrides: relationships.state(of: key),
                    // Aggressive, not Very Aggressive: the Creation Kit's table
                    // says Aggressive "will attack Enemies on sight" and Very
                    // Aggressive attacks neutrals too, so only Aggressive lets
                    // an enemy relation and no relation give different answers.
                    aiData: Social.aiData(aggression: .aggressive)
                )
            }
            let derivation = factions.derivation
            return PapyrusSocialDecision(
                isHostile: derivation.decide(profiles[0], toward: profiles[1]).isHostile,
                factionReaction: derivation
                    .factionReaction(of: profiles[0], toward: profiles[1]) ?? .neutral
            )
        }
    }

    @discardableResult
    private func call(
        _ scriptName: String,
        _ functionName: String,
        _ fixture: Fixture,
        receiver: PapyrusObjectHandle,
        arguments: [PapyrusValue] = [],
        returnType: PapyrusType = .none
    ) -> PapyrusNativeResult {
        fixture.registry.invoke(PapyrusWorldFixture.methodCall(
            scriptName,
            functionName,
            receiver: receiver,
            arguments: arguments,
            returnType: returnType
        ))
    }

    private func isFailure(_ result: PapyrusNativeResult) -> Bool {
        if case .failed = result {
            return true
        }
        return false
    }

    /// A FACT's own handle, which is what a `Faction` script's `self` is and what
    /// a `Faction` argument to an `Actor` native carries.
    private func handle(
        _ fixture: Fixture,
        faction: ReferenceKey
    ) throws -> PapyrusObjectHandle {
        try #require(fixture.session.bridge.objectHandle(for: faction))
    }

    private func rank(
        _ fixture: Fixture,
        _ faction: PapyrusObjectHandle
    ) -> PapyrusNativeResult {
        call(
            "Actor", "GetFactionRank", fixture,
            receiver: fixture.actor,
            arguments: [.object(faction)],
            returnType: .integer
        )
    }

    private func isHostileCall(_ fixture: Fixture) -> PapyrusNativeResult {
        call(
            "Actor", "IsHostileToActor", fixture,
            receiver: fixture.actor,
            arguments: [.object(fixture.other)],
            returnType: .boolean
        )
    }

    private func relationship(
        _ fixture: Fixture,
        reversed: Bool = false
    ) -> PapyrusNativeResult {
        call(
            "Actor", "GetRelationshipRank", fixture,
            receiver: reversed ? fixture.other : fixture.actor,
            arguments: [.object(reversed ? fixture.actor : fixture.other)],
            returnType: .integer
        )
    }
}
