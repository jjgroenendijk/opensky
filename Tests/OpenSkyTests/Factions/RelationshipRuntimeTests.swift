// Runtime relationship ranks (issue #508, roadmap item 21.4): the component's
// normalization, the two-layer lookup, the both-directions write, and the `RELS`
// save round trip.
//
// Fixtures are synthetic — never extracted game files (AGENTS.md "Legal & IP
// boundary").

import Foundation
@testable import OpenSkyEngine
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import Testing

@MainActor
struct RelationshipRuntimeTests {
    private typealias Fixture = HostilityFixture

    private let guardKey = ReferenceKey.plugin(name: "base.esm", objectID: 0x2000)
    private let banditKey = ReferenceKey.plugin(name: "base.esm", objectID: 0x2001)

    // MARK: - The component

    /// Setting the same actor twice replaces the rank rather than adding a
    /// second row, because "what are these two to each other" must have exactly
    /// one answer.
    @Test func settingTwiceReplacesTheRank() {
        let state = ActorRelationshipState()
            .setting(2, toward: banditKey)
            .setting(-1, toward: banditKey)

        #expect(state.count == 1)
        #expect(state.rank(toward: banditKey) == -1)
    }

    /// The component normalizes into ascending key order on the way in, which is
    /// what makes the save write the same bytes twice for the same state.
    @Test func overridesAreStoredInKeyOrder() {
        let state = ActorRelationshipState(overrides: [
            ActorRelationshipOverride(other: banditKey, rank: 1),
            ActorRelationshipOverride(other: guardKey, rank: 2)
        ])

        #expect(state.overrides.map(\.other) == [guardKey, banditKey].sorted())
    }

    /// Nil is not 0: 0 is Acquaintance, a rank a record and a script both author
    /// deliberately.
    @Test func anUnsetPairReportsNilRatherThanAcquaintance() {
        let state = ActorRelationshipState().setting(0, toward: banditKey)

        #expect(state.rank(toward: banditKey) == 0)
        #expect(state.rank(toward: guardKey) == nil)
    }

    // MARK: - The runtime

    /// Both components are written, so either actor answers alone — which is
    /// what makes the lookup symmetric the way a `RELA` record is.
    @Test func settingARankWritesBothDirections() throws {
        let store = WorldStateStore()
        let runtime = try Self.runtime(store: store)

        #expect(runtime.setRank(3, of: guardKey, toward: banditKey))

        #expect(runtime.state(of: guardKey).rank(toward: banditKey) == 3)
        #expect(runtime.state(of: banditKey).rank(toward: guardKey) == 3)
        #expect(runtime.storedRank(of: banditKey, toward: guardKey) == 3)
    }

    /// An unchanged write reports no change, so a script re-setting the same rank
    /// does not dirty the save.
    @Test func rewritingTheSameRankChangesNothing() throws {
        let runtime = try Self.runtime()
        runtime.setRank(3, of: guardKey, toward: banditKey)

        #expect(!runtime.setRank(3, of: guardKey, toward: banditKey))
    }

    /// No `RELA` record names a base twice, so an actor set against itself is
    /// refused rather than stored as a question the records cannot pose.
    @Test func anActorCannotBeGivenARankTowardItself() throws {
        let runtime = try Self.runtime()

        #expect(!runtime.setRank(4, of: guardKey, toward: guardKey))
        #expect(runtime.state(of: guardKey).isEmpty)
    }

    /// The record layer answers in either argument order, over the signed
    /// "4 Lover ... -4 Archnemesis" table.
    @Test func theRecordAnswersWhenNoScriptHasSpoken() throws {
        let runtime = try Self.runtime(pairs: [
            Fixture.Pair(Fixture.Actors.cityGuard, Fixture.Actors.bandit, .confidant)
        ])

        #expect(runtime.rank(of: guardKey, toward: banditKey, bases: bases) == 2)
        #expect(runtime.rank(of: banditKey, toward: guardKey, bases: bases) == 2)
    }

    /// A scripted rank wins over the record, which is what "set" means.
    @Test func theScriptedRankWinsOverTheRecord() throws {
        let runtime = try Self.runtime(pairs: [
            Fixture.Pair(Fixture.Actors.cityGuard, Fixture.Actors.bandit, .confidant)
        ])

        runtime.setRank(-4, of: guardKey, toward: banditKey)

        #expect(runtime.rank(of: guardKey, toward: banditKey, bases: bases) == -4)
    }

    /// The player has no `NPC_` base, so only the override layer can name a pair
    /// they are in — which is the case nearly every vanilla script cares about.
    @Test func aPairInvolvingThePlayerAnswersFromTheOverrideAlone() throws {
        let runtime = try Self.runtime()

        #expect(runtime.rank(of: guardKey, toward: .player, bases: bases) == nil)
        runtime.setRank(4, of: guardKey, toward: .player)
        #expect(runtime.rank(of: guardKey, toward: .player, bases: bases) == 4)
    }

    // MARK: - Hostility

    /// "Relationships override factions" (<https://ck.uesp.net/wiki/Relationship>),
    /// and a scripted rank is a relationship — so setting one to Archnemesis
    /// makes an otherwise allied pair read as enemies.
    @Test func aScriptedRankMovesTheDerivedReaction() throws {
        let derivation = try Fixture.derivation(relations: [
            Fixture.Relation(Fixture.Factions.guards, Fixture.Factions.bandit, .ally)
        ])
        let observer = Fixture.profile(
            actor: Fixture.Actors.cityGuard,
            memberships: [(Fixture.Factions.guards, 0)],
            relationships: [(Fixture.key(Fixture.Actors.bandit), -4)]
        )
        let target = Fixture.profile(
            actor: Fixture.Actors.bandit,
            memberships: [(Fixture.Factions.bandit, 0)]
        )

        #expect(derivation.reaction(of: observer, toward: target) == .enemy)
        #expect(derivation.decide(observer, toward: target).source == .relationship)
    }

    // MARK: - The RELS chunk

    @Test func overridesSurviveTheSaveRoundTrip() throws {
        let state = ActorRelationshipState(overrides: [
            ActorRelationshipOverride(other: banditKey, rank: -2),
            ActorRelationshipOverride(other: .player, rank: 4),
            ActorRelationshipOverride(other: .generated(7), rank: 0)
        ])

        let restored = try #require(Self.roundTrip(state, for: guardKey))

        #expect(restored == state)
        #expect(restored.rank(toward: .player) == 4)
        // A rank of 0 is a real rank and has to survive as one.
        #expect(restored.rank(toward: .generated(7)) == 0)
    }

    /// A session in which no script touched a relationship writes no chunk at
    /// all, so its bytes match what this encoder produced before `RELS` existed.
    @Test func aSessionWithNoOverridesWritesNoChunk() {
        let store = WorldStateStore()
        store.set(ActorFactionState(memberships: [
            ActorFactionMembership(faction: guardKey, rank: 1)
        ]), for: banditKey, in: nil)

        let data = Self.encode(store.snapshot())

        #expect(!Self.contains(OpenSkySaveFormat.ChunkTag.relationships, in: data))
    }

    /// Re-encoding an unchanged component produces identical bytes, which is
    /// what the component's key ordering is for.
    @Test func encodingIsStable() {
        let state = ActorRelationshipState(overrides: [
            ActorRelationshipOverride(other: banditKey, rank: 1),
            ActorRelationshipOverride(other: .player, rank: -1)
        ])
        let store = WorldStateStore()
        store.set(state, for: guardKey, in: nil)

        #expect(Self.encode(store.snapshot()) == Self.encode(store.snapshot()))
    }

    // MARK: - Fixture

    /// A reference-to-base map in the shape the session supplies one, with the
    /// player deliberately absent.
    private var bases: (ReferenceKey) -> ResolvedFormID? {
        let table: [ReferenceKey: ResolvedFormID] = [
            guardKey: Fixture.id(Fixture.Actors.cityGuard),
            banditKey: Fixture.id(Fixture.Actors.bandit)
        ]
        return { table[$0] }
    }

    private static func runtime(
        store: WorldStateStore = WorldStateStore(),
        pairs: [Fixture.Pair] = []
    ) throws -> RelationshipRuntime {
        try RelationshipRuntime(
            store: store,
            relationships: RelationshipStore(
                plugins: [(Fixture.pluginName, Fixture.file(pairs: pairs))]
            )
        )
    }

    private static func encode(_ snapshot: WorldStateSnapshot) -> Data {
        OpenSkySaveEncoder.encode(
            snapshot: snapshot,
            fingerprint: OpenSkySaveFixture.fingerprint,
            metadata: OpenSkySaveFixture.metadata
        )
    }

    private static func roundTrip(
        _ component: ActorRelationshipState,
        for key: ReferenceKey
    ) -> ActorRelationshipState? {
        let store = WorldStateStore()
        store.set(component, for: key, in: nil)
        guard let file = try? OpenSkySaveDecoder.decode(encode(store.snapshot())) else {
            return nil
        }
        return file.snapshot.entries
            .first { $0.key == key }?
            .delta
            .component(ActorRelationshipState.self)
    }

    /// Whether a four-character chunk tag appears in the encoded bytes.
    private static func contains(_ tag: String, in data: Data) -> Bool {
        guard let needle = tag.data(using: .ascii) else { return false }
        return data.range(of: needle) != nil
    }
}
