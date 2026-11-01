// The `RELF` chunk, where each pair's first-friend rank lays back onto its `RELS` row,
// and the `STOF` chunk of what the player stole from each owning faction.

import Foundation
@testable import OpenSkyCrimeInterface
@testable import OpenSkyFactionsInterface
@testable import OpenSkyFormatsESM
@testable import OpenSkySave
import OpenSkySaveFixtures
@testable import OpenSkyWorldState
import Testing

@MainActor
struct RelationshipFavourSaveTests {
    private let friend = ReferenceKey.plugin(name: "base.esm", objectID: 0x2000)
    private let rival = ReferenceKey.plugin(name: "base.esm", objectID: 0x2001)

    private static func encode(_ store: WorldStateStore) -> Data {
        OpenSkySaveEncoder.encode(
            snapshot: store.snapshot(),
            fingerprint: OpenSkySaveFixture.fingerprint,
            metadata: OpenSkySaveFixture.metadata
        )
    }

    @Test func theFirstFriendRankSurvivesTheRoundTrip() throws {
        let state = ActorRelationshipState()
            .setting(1, toward: friend)
            .setting(4, toward: friend)
            .setting(-2, toward: rival)
        let store = WorldStateStore()
        store.set(state, for: .player, in: nil)

        let file = try OpenSkySaveDecoder.decode(Self.encode(store))
        let restored = file.snapshot.entries.first { $0.key == .player }?
            .delta.component(ActorRelationshipState.self)

        #expect(restored == state)
        #expect(restored?.firstFriendRank(toward: friend) == 1)
        #expect(restored?.firstFriendRank(toward: rival) == nil)
    }

    @Test func noFriendWritesNoChunk() {
        let store = WorldStateStore()
        store.set(ActorRelationshipState().setting(0, toward: rival), for: .player, in: nil)
        let bytes = Self.encode(store)
        #expect(bytes.range(of: Data(OpenSkySaveFormat.ChunkTag.relationshipFavour.utf8)) == nil)
    }

    @Test func stolenOriginsSurviveTheRoundTrip() throws {
        let state = StolenOriginsState()
            .adding(FormID(0xA01), count: 3, from: rival)
            .adding(FormID(0xA02), count: 1, from: friend)
        let store = WorldStateStore()
        store.set(state, for: .player, in: nil)
        let file = try OpenSkySaveDecoder.decode(Self.encode(store))
        #expect(file.snapshot.entries.first { $0.key == .player }?
            .delta.component(StolenOriginsState.self) == state)
    }
}
