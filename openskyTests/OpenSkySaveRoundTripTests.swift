// Round-trip and determinism tests for the OpenSky native save container
// (issue #161).
//
// The determinism case drives a real `WorldStateStore` rather than building a
// snapshot by hand, because the property that matters is "two sessions that
// reached the same end state write the same bytes", and only the store can
// reach an end state through a different route. The store is @MainActor, so
// this suite is too.

import Foundation
@testable import opensky
import simd
import Testing

@MainActor
struct OpenSkySaveRoundTripTests {
    // MARK: - Fixtures

    private let whiterun = CellSceneLocation.exterior(CellCoordinate(x: 5, y: -1))
    private let inn = CellSceneLocation.interior(FormID(0x1234))

    private func key(_ objectID: UInt32) -> ReferenceKey {
        .plugin(name: "skyrim.esm", objectID: objectID)
    }

    private func encode(_ snapshot: WorldStateSnapshot) -> Data {
        OpenSkySaveEncoder.encode(
            snapshot: snapshot,
            fingerprint: OpenSkySaveFixture.fingerprint,
            metadata: OpenSkySaveFixture.metadata
        )
    }

    /// Reaches one end state by writing the components of two references in
    /// ascending order, with an intermediate value that is later overwritten.
    private func storeInOneOrder() -> WorldStateStore {
        let store = WorldStateStore()
        store.set(ReferenceEnableState.enabled, for: key(0x200), in: whiterun)
        store.set(ReferenceEnableState.disabled, for: key(0x200), in: whiterun)
        store.set(
            ReferenceTransformOverride(position: SIMD3(1, 2, 3), scale: 2),
            for: key(0x200),
            in: whiterun
        )
        store.set(
            ReferenceActivationState(activationCount: 3, isOpen: true, lastActivator: key(0x14)),
            for: key(0x200),
            in: whiterun
        )
        store.set(ReferenceDeletionState.deleted, for: key(0x200), in: whiterun)
        store.set(
            ReferenceTransformOverride(position: SIMD3(-4, 0, 0.5), scale: 1),
            for: key(0x201),
            in: inn
        )
        for _ in 0 ..< 3 {
            _ = store.allocateGeneratedKey()
        }
        return store
    }

    /// The same end state reached back to front, across references and across
    /// component slots, with one reference mutated and then fully reset.
    private func storeInAnotherOrder() -> WorldStateStore {
        let store = WorldStateStore()
        store.set(ReferenceEnableState.disabled, for: key(0x202), in: inn)
        store.set(
            ReferenceTransformOverride(position: SIMD3(-4, 0, 0.5), scale: 1),
            for: key(0x201),
            in: inn
        )
        store.set(ReferenceDeletionState.deleted, for: key(0x200), in: whiterun)
        store.set(
            ReferenceActivationState(activationCount: 3, isOpen: true, lastActivator: key(0x14)),
            for: key(0x200),
            in: whiterun
        )
        store.set(
            ReferenceTransformOverride(position: SIMD3(1, 2, 3), scale: 2),
            for: key(0x200),
            in: whiterun
        )
        store.set(ReferenceEnableState.disabled, for: key(0x200), in: whiterun)
        store.reset(key(0x202))
        for _ in 0 ..< 3 {
            _ = store.allocateGeneratedKey()
        }
        return store
    }

    // MARK: - Determinism

    @Test func twoMutationOrdersReachingOneStateEncodeIdenticalBytes() {
        let first = storeInOneOrder().snapshot()
        let second = storeInAnotherOrder().snapshot()
        #expect(first == second)
        #expect(first.dirtyCount == 2)
        #expect(first.nextGeneratedSequence == 4)
        #expect(encode(first) == encode(second))
    }

    @Test func encodingTheSameSnapshotTwiceGivesTheSameBytes() {
        let snapshot = OpenSkySaveFixture.richSnapshot()
        #expect(encode(snapshot) == encode(snapshot))
    }

    @Test func onlyTheHeaderDependsOnTheCreationTimestamp() {
        let snapshot = OpenSkySaveFixture.richSnapshot()
        let early = OpenSkySaveEncoder.encode(
            snapshot: snapshot,
            fingerprint: OpenSkySaveFixture.fingerprint,
            metadata: SaveCreationMetadata(creationTimestamp: 1, appVersion: "9.9.9")
        )
        let late = OpenSkySaveEncoder.encode(
            snapshot: snapshot,
            fingerprint: OpenSkySaveFixture.fingerprint,
            metadata: SaveCreationMetadata(creationTimestamp: 2, appVersion: "9.9.9")
        )
        let headerLength = OpenSkySaveFixture.fingerprintOffset(in: early)
        #expect(headerLength == OpenSkySaveFixture.fingerprintOffset(in: late))
        #expect(early.count == late.count)
        #expect(early != late)
        #expect(Data(early.dropFirst(headerLength)) == Data(late.dropFirst(headerLength)))
    }

    // MARK: - Round trips

    @Test func richSnapshotSurvivesAnEncodeAndDecode() throws {
        let snapshot = OpenSkySaveFixture.richSnapshot()
        let file = try OpenSkySaveDecoder.decode(encode(snapshot))

        #expect(file.formatVersion == OpenSkySaveFormat.currentVersion)
        #expect(file.metadata == OpenSkySaveFixture.metadata)
        #expect(file.fingerprint == OpenSkySaveFixture.fingerprint)
        #expect(file.snapshot == snapshot)
        #expect(file.snapshot.keys == snapshot.keys)
        // The journal position is session-local bookkeeping, never saved.
        #expect(file.snapshot.sequence == 0)
        #expect(file.snapshot.nextGeneratedSequence == 77)
        #expect(file.allocator.nextSequence == 77)
    }

    @Test func everyShapeOfEntryComesBackUnchanged() throws {
        let file = try OpenSkySaveDecoder.decode(OpenSkySaveFixture.encodedRichSave())
        let decoded = file.snapshot

        let dawnguard = ReferenceKey.plugin(name: "dawnguard.esm", objectID: 0x000A_BCDE)
        let delta = try #require(decoded[dawnguard])
        #expect(delta.cell == OpenSkySaveFixture.whiterun)
        #expect(delta.sortedKinds == WorldStateComponentKind.allCases)
        #expect(delta.component(ReferenceEnableState.self)?.isEnabled == false)
        let transform = try #require(delta.component(ReferenceTransformOverride.self))
        #expect(transform.position == SIMD3(-1.5, 2.25, 3e10))
        #expect(transform.rotation == SIMD3(0.5, -0.25, 0))
        #expect(transform.scale == 1.75)
        let activation = try #require(delta.component(ReferenceActivationState.self))
        #expect(activation.activationCount == 9)
        #expect(activation.isOpen)
        #expect(activation.lastActivator == OpenSkySaveFixture.activator)
        #expect(delta.component(ReferenceDeletionState.self)?.isDeleted == true)

        // Interior cell, no cell at all, and a generated key with an activation
        // that has no last activator.
        #expect(decoded[.plugin(name: "skyrim.esm", objectID: 1)]?.cell == OpenSkySaveFixture.inn)
        let nonASCII = ReferenceKey.plugin(name: "vílja í skyrim.esp", objectID: 0x00FF_FFFF)
        let nonASCIIDelta = try #require(decoded[nonASCII])
        #expect(nonASCIIDelta.cell == nil)
        #expect(nonASCIIDelta.sortedKinds == [.enableState, .deletion])
        let generated = try #require(decoded[.generated(42)])
        #expect(generated.cell == OpenSkySaveFixture.riverwood)
        #expect(generated.component(ReferenceActivationState.self)?.lastActivator == nil)
    }

    @Test func emptySnapshotRoundTrips() throws {
        let encoded = encode(WorldStateSnapshot.empty)
        let file = try OpenSkySaveDecoder.decode(encoded)
        #expect(file.snapshot == WorldStateSnapshot.empty)
        #expect(file.snapshot.isEmpty)
        #expect(file.allocator.nextSequence == 1)
        #expect(file.fingerprint == OpenSkySaveFixture.fingerprint)
    }

    @Test func emptyFingerprintRoundTrips() throws {
        let encoded = OpenSkySaveEncoder.encode(
            snapshot: WorldStateSnapshot.empty,
            fingerprint: [],
            metadata: OpenSkySaveFixture.metadata
        )
        #expect(try OpenSkySaveDecoder.decode(encoded).fingerprint.isEmpty)
    }

    // MARK: - Tolerance

    @Test func unknownChunksAreSkippedWhereverTheyAppear() throws {
        let unknown = OpenSkySaveFixture.chunk("ZZZZ", OpenSkySaveFixture.bytes([1, 2, 3, 4, 5]))
        var data = OpenSkySaveFixture.encodedRichSave()
        let expected = try OpenSkySaveDecoder.decode(data)

        // After the known chunks, then between them, then before them: each
        // insertion offset is recomputed so the earlier ones do not shift it.
        data.append(unknown)
        let between = try #require(
            OpenSkySaveFixture.offset(ofChunk: OpenSkySaveFormat.ChunkTag.referenceDeltas, in: data)
        )
        data = OpenSkySaveFixture.inserting(unknown, into: data, at: between)
        let before = try #require(
            OpenSkySaveFixture.offset(ofChunk: OpenSkySaveFormat.ChunkTag.allocator, in: data)
        )
        data = OpenSkySaveFixture.inserting(unknown, into: data, at: before)

        let file = try OpenSkySaveDecoder.decode(data)
        #expect(file.snapshot == expected.snapshot)
        #expect(file.allocator == expected.allocator)
        #expect(file.fingerprint == expected.fingerprint)
        #expect(file.metadata == expected.metadata)
    }

    @Test func aFileWithNoAllocatorChunkStartsTheAllocatorAtOne() throws {
        let data = OpenSkySaveFixture.file(chunks: [OpenSkySaveFixture.deltasChunk(count: 0)])
        let file = try OpenSkySaveDecoder.decode(data)
        #expect(file.allocator.nextSequence == 1)
        #expect(file.snapshot.nextGeneratedSequence == 1)
        #expect(file.snapshot.isEmpty)
    }

    @Test func aFileWithNoChunksAtAllDecodesToTheEmptyState() throws {
        let file = try OpenSkySaveDecoder.decode(OpenSkySaveFixture.file(chunks: []))
        #expect(file.snapshot == WorldStateSnapshot.empty)
        #expect(file.fingerprint == OpenSkySaveFixture.fingerprint)
    }

    @Test func unknownTrailingMetadataBytesAreSkipped() throws {
        var data = OpenSkySaveFixture.encodedRichSave()
        let expected = try OpenSkySaveDecoder.decode(data)
        let extra = OpenSkySaveFixture.bytes([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x00])
        let blockLength = OpenSkySaveFixture.metadataBlockLength(in: data)
        data = OpenSkySaveFixture.inserting(extra, into: data, at: 12 + blockLength)
        var length = BinaryWriter()
        length.writeUInt32(UInt32(blockLength + extra.count))
        data = OpenSkySaveFixture.patching(data, at: 8, with: Array(length.data))

        let file = try OpenSkySaveDecoder.decode(data)
        #expect(file.metadata == expected.metadata)
        #expect(file.snapshot == expected.snapshot)
    }
}
