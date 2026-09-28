// The `PRKS` chunk (issue #497, roadmap item 20.4): the owned-perk round trip,
// the normalization a load has to survive, and the absent-chunk case that keeps
// a save with no perks byte-identical to what this encoder produced before the
// chunk existed.

import Foundation
@testable import opensky
import Testing

@MainActor
struct PerkSaveTests {
    private let first = PerkRuntimeFixture.key(PerkRuntimeFixture.Perk.damageRank1)
    private let second = PerkRuntimeFixture.key(PerkRuntimeFixture.Perk.damageRank2)
    private let blocking = PerkRuntimeFixture.key(PerkRuntimeFixture.Perk.blocking)

    private static func encode(_ snapshot: WorldStateSnapshot) -> Data {
        OpenSkySaveEncoder.encode(
            snapshot: snapshot,
            fingerprint: OpenSkySaveFixture.fingerprint,
            metadata: OpenSkySaveFixture.metadata
        )
    }

    private func roundTrip(_ state: PerkState) throws -> PerkState? {
        let store = WorldStateStore()
        store.set(state, for: .player, in: nil)
        let data = Self.encode(store.snapshot())
        let file = try OpenSkySaveDecoder.decode(data)
        return file.snapshot.entries.first { $0.key == ReferenceKey.player }?
            .delta.component(PerkState.self)
    }

    @Test func ownedPerksSurviveTheRoundTrip() throws {
        let state = PerkState(owned: [second, first, blocking])

        let restored = try #require(try roundTrip(state))

        #expect(restored == state)
        #expect(restored.owned == [first, second, blocking].sorted())
    }

    /// A generated key round-trips beside a plugin one, which is what an actor
    /// the running game created carries.
    @Test func aGeneratedOwnerRoundTripsToo() throws {
        let store = WorldStateStore()
        store.set(PerkState(owned: [blocking]), for: .generated(7), in: nil)

        let file = try OpenSkySaveDecoder.decode(Self.encode(store.snapshot()))

        let restored = file.snapshot.entries.first { $0.key == ReferenceKey.generated(7) }?
            .delta.component(PerkState.self)
        #expect(restored?.owned == [blocking])
    }

    @Test func aSessionInWhichNobodyOwnsAPerkWritesNoChunk() {
        let store = WorldStateStore()

        let data = Self.encode(store.snapshot())

        #expect(!data.contains(Data(OpenSkySaveFormat.ChunkTag.perks.utf8)))
    }

    /// Duplicates collapse on the way back in, which is what makes the
    /// component the decoder's entry point rather than a bag the decoder has to
    /// validate.
    @Test func aDuplicateEntryCollapsesOnLoad() throws {
        let restored = try roundTrip(PerkState(owned: [blocking, blocking]))

        #expect(restored?.owned == [blocking])
    }
}
