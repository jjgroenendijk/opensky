// The `FCTN` chunk (issue #503, roadmap item 21.3): the membership round trip,
// the normalization a load has to survive, and the absent-chunk case that keeps
// a save with no memberships byte-identical to what this encoder produced
// before the chunk existed.

import Foundation
@testable import opensky
import Testing

@MainActor
struct FactionMembershipSaveTests {
    private let bandits = ReferenceKey.plugin(name: "base.esm", objectID: 0x10)
    private let guards = ReferenceKey.plugin(name: "base.esm", objectID: 0x11)
    private let generated = ReferenceKey.generated(4)

    private static func encode(_ snapshot: WorldStateSnapshot) -> Data {
        OpenSkySaveEncoder.encode(
            snapshot: snapshot,
            fingerprint: OpenSkySaveFixture.fingerprint,
            metadata: OpenSkySaveFixture.metadata
        )
    }

    private func roundTrip(
        _ state: ActorFactionState,
        for key: ReferenceKey = .player
    ) throws -> ActorFactionState? {
        let store = WorldStateStore()
        store.set(state, for: key, in: nil)
        let file = try OpenSkySaveDecoder.decode(Self.encode(store.snapshot()))
        return file.snapshot.entries.first { $0.key == key }?
            .delta.component(ActorFactionState.self)
    }

    @Test func membershipsAndRanksSurviveTheRoundTrip() throws {
        let state = ActorFactionState(memberships: [
            ActorFactionMembership(faction: guards, rank: 3),
            ActorFactionMembership(faction: bandits, rank: -1),
            ActorFactionMembership(faction: generated, rank: 127)
        ])

        let restored = try #require(try roundTrip(state))

        #expect(restored == state)
        #expect(restored.rank(in: bandits) == -1)
        #expect(restored.rank(in: guards) == 3)
        #expect(restored.rank(in: generated) == 127)
        // Key order, plugin keys before generated ones.
        #expect(restored.factions == [bandits, guards, generated])
    }

    /// A negative rank is what the Creation Kit writes for "a member the rank
    /// titles do not name", and vanilla authors them, so the sign has to
    /// survive the byte.
    @Test func theFullSignedRankRangeSurvives() throws {
        let state = ActorFactionState(memberships: [
            ActorFactionMembership(faction: bandits, rank: -128)
        ])

        #expect(try roundTrip(state)?.rank(in: bandits) == -128)
    }

    @Test func anActorWithNoOtherDeltaStillGetsAnEntry() throws {
        let store = WorldStateStore()
        store.set(
            ActorFactionState(memberships: [
                ActorFactionMembership(faction: bandits, rank: 0)
            ]),
            for: generated,
            in: nil
        )

        let file = try OpenSkySaveDecoder.decode(Self.encode(store.snapshot()))

        let restored = file.snapshot.entries.first { $0.key == generated }?
            .delta.component(ActorFactionState.self)
        #expect(restored?.factions == [bandits])
    }

    @Test func aSessionInWhichNobodyJoinedAnythingWritesNoChunk() {
        let store = WorldStateStore()

        let data = Self.encode(store.snapshot())

        #expect(!data.contains(Data(OpenSkySaveFormat.ChunkTag.factions.utf8)))
    }

    /// Re-encoding the same state has to produce the same bytes, which is what
    /// the component's ordering rule exists for.
    @Test func reEncodingAnUnchangedStateIsByteIdentical() {
        let first = WorldStateStore()
        let second = WorldStateStore()
        let memberships = [
            ActorFactionMembership(faction: guards, rank: 1),
            ActorFactionMembership(faction: bandits, rank: 2)
        ]
        first.set(ActorFactionState(memberships: memberships), for: .player, in: nil)
        second.set(ActorFactionState(memberships: memberships.reversed()), for: .player, in: nil)

        #expect(Self.encode(first.snapshot()) == Self.encode(second.snapshot()))
    }
}
