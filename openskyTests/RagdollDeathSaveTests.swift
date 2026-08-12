// DETH chunk tests (issue #197): the additive death chunk in the OpenSky native
// save container.
//
// The same promises `AVAL` makes, for the same reasons: a save carrying a
// corpse must still load in a build that knows nothing about the chunk, and
// `RDLT` must gain nothing so an actor whose only component is its death leaves
// no entry there for an older build to restore as an empty reference.
//
// Beyond the round trip, this suite pins the item's stated persistence choice:
// a corpse comes back dead, at the position and facing it settled at, and
// without the per-bone pose it died in.

import Foundation
@testable import opensky
import simd
import Testing

@MainActor
struct RagdollDeathSaveTests {
    private let corpse = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0001_3BAC)
    private let looted = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0001_3BAD)

    private func settled() -> ActorDeathState {
        ActorDeathState.justDied.settled(
            at: SIMD3(1200.5, -340.25, 68.75),
            orientation: simd_quatf(angle: .pi / 3, axis: SIMD3(0, 0, 1))
        )
    }

    /// A snapshot with three shapes: a settled corpse whose only delta is its
    /// death, a looted corpse still falling (so no resting transform), and an
    /// ordinary reference that never died.
    private func snapshot() -> WorldStateSnapshot {
        let entries = [
            OpenSkySaveFixture.entry(
                key: corpse,
                cell: OpenSkySaveFixture.whiterun,
                components: [settled().erased]
            ),
            OpenSkySaveFixture.entry(
                key: looted,
                cell: OpenSkySaveFixture.whiterun,
                components: [ActorDeathState.justDied.looted.erased]
            ),
            OpenSkySaveFixture.entry(
                key: .plugin(name: "skyrim.esm", objectID: 1),
                cell: OpenSkySaveFixture.riverwood,
                components: [ReferenceDeletionState.deleted.erased]
            )
        ]
        return WorldStateSnapshot(
            entries: entries.sorted { $0.key < $1.key },
            nextGeneratedSequence: 5,
            sequence: 11
        )
    }

    private func encode(_ snapshot: WorldStateSnapshot) -> Data {
        OpenSkySaveEncoder.encode(
            snapshot: snapshot,
            fingerprint: OpenSkySaveFixture.fingerprint,
            metadata: OpenSkySaveFixture.metadata
        )
    }

    // MARK: - Round trip

    @Test func deathsSurviveAnEncodeAndDecode() throws {
        let original = snapshot()
        let file = try OpenSkySaveDecoder.decode(encode(original))
        #expect(file.snapshot == original)

        let delta = try #require(file.snapshot[corpse])
        #expect(delta.sortedKinds == [.death])
        #expect(delta.cell == OpenSkySaveFixture.whiterun)
        #expect(delta.component(ActorDeathState.self) == settled())
    }

    /// A corpse still falling when the save was written carries no resting
    /// transform, and comes back that way rather than with an invented one.
    @Test func aCorpseWithNoRestingPoseRoundTripsAsSuch() throws {
        let file = try OpenSkySaveDecoder.decode(encode(snapshot()))
        let state = try #require(file.snapshot[looted]?.component(ActorDeathState.self))
        #expect(state.isDead)
        #expect(state.wasLooted)
        #expect(state.restingTransform == nil)
    }

    /// Restoring a decoded save into a live store leaves the actor dead and
    /// posed at rest, which is the property the item's acceptance names.
    @Test func restoringASaveBringsTheCorpseBackDeadAndAtRest() throws {
        let file = try OpenSkySaveDecoder.decode(encode(snapshot()))
        let store = WorldStateStore()
        store.restore(from: file.snapshot)
        let state = try #require(store.component(ActorDeathState.self, for: corpse))
        #expect(state.isDead)
        let resting = try #require(state.restingTransform)
        let recorded = try #require(settled().restingTransform)
        #expect(resting.position == SIMD3(1200.5, -340.25, 68.75))
        // The rotation is compared against what the settle recorded rather than
        // against the quaternion it came from: `MatrixMath.eulerAngles` owns the
        // convention, and this suite is about the bytes surviving the trip.
        #expect(resting.rotation == recorded.rotation)
        #expect(resting.scale == recorded.scale)
        #expect(store.snapshot() == file.snapshot)
    }

    @Test func decodedEntriesStayInReferenceKeyOrder() throws {
        let file = try OpenSkySaveDecoder.decode(encode(snapshot()))
        #expect(file.snapshot.keys == file.snapshot.keys.sorted())
    }

    /// Two stores that reached the same end state write identical bytes.
    @Test func encodingIsDeterministic() {
        #expect(encode(snapshot()) == encode(snapshot()))
    }

    // MARK: - Additive-chunk tolerance

    /// A session in which nothing died writes no `DETH` chunk at all.
    @Test func aSaveWithNoDeathsCarriesNoChunk() {
        let encoded = encode(OpenSkySaveFixture.richSnapshot())
        #expect(OpenSkySaveFixture.offset(
            ofChunk: OpenSkySaveFormat.ChunkTag.deaths, in: encoded
        ) == nil)
    }

    /// The older-build case: the same file with the chunk tag renamed to one
    /// nothing knows decodes cleanly, losing only the deaths.
    @Test func anUnknownChunkTagIsSkippedByItsLength() throws {
        let encoded = encode(snapshot())
        let offset = try #require(OpenSkySaveFixture.offset(
            ofChunk: OpenSkySaveFormat.ChunkTag.deaths, in: encoded
        ))
        let renamed = OpenSkySaveFixture.patching(
            encoded, at: offset, with: Array("ZZZZ".utf8)
        )
        let file = try OpenSkySaveDecoder.decode(renamed)
        #expect(file.snapshot[corpse] == nil)
        #expect(file.snapshot[.plugin(name: "skyrim.esm", objectID: 1)] != nil)
    }

    /// `RDLT` must not carry a death component, so an older build restores the
    /// world without one rather than failing on an unknown tag.
    @Test func rdltRejectsADeathComponentTag() {
        #expect(WorldStateComponentKind.death.saveTag == nil)
    }

    // MARK: - Corruption

    @Test func anImpossibleEntryCountIsRejected() {
        var payload = BinaryWriter()
        payload.writeUInt32(0xFFFF_FFFF)
        #expect(throws: OpenSkySaveError.self) {
            try OpenSkySaveDeathDecoder.decodeDeaths(payload.data)
        }
    }

    /// A truncated entry is a thrown error rather than a partial state: the
    /// resting transform says it is present and then the bytes run out.
    @Test func aTruncatedEntryIsRejected() {
        var payload = BinaryWriter()
        payload.writeUInt32(1)
        payload.writeUInt8(OpenSkySaveFormat.KeyTag.generated)
        payload.writeUInt64(0)
        payload.writeUInt8(OpenSkySaveFormat.CellTag.absent)
        payload.writeUInt8(1)
        payload.writeUInt8(0)
        payload.writeUInt8(1)
        #expect(throws: OpenSkySaveError.self) {
            try OpenSkySaveDeathDecoder.decodeDeaths(payload.data)
        }
    }
}
