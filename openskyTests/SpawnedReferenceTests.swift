// Spawned-reference component and SPWN save chunk tests (issue #177, roadmap
// item 12.1.3): identity synthesis, value normalization, and the round trip
// through the native save container alongside the other chunks.

import Foundation
@testable import opensky
import simd
import Testing

struct SpawnedReferenceTests {
    private static let cell = CellSceneLocation.exterior(CellCoordinate(x: 12, y: -3))
    private static let interior = CellSceneLocation.interior(FormID(0x0001_A5B0))

    private static func spawn(
        base: UInt32 = 0x0000_0100,
        location: CellSceneLocation = cell,
        position: SIMD3<Float> = SIMD3(1.5, -2.5, 3.5),
        scale: Float = 1,
        count: Int32 = 1
    ) -> ReferenceSpawnState {
        ReferenceSpawnState(
            base: FormID(base),
            location: location,
            placement: PlacedReference.Placement(position: position, rotation: SIMD3(0, 0, 0.25)),
            scale: scale,
            count: count
        )
    }

    private static func metadata() -> SaveCreationMetadata {
        SaveCreationMetadata(creationTimestamp: 1_700_000_000, appVersion: "test")
    }

    // MARK: - Identity

    /// A generated sequence becomes a `0xFF`-prefixed FormID, which no plugin
    /// record can ever carry because a load order holds at most 0xFE plugins.
    @Test func generatedKeysMapOntoTheReservedModIndex() {
        #expect(SpawnedReferenceIdentity.formID(for: .generated(1)) == FormID(0xFF00_0001))
        #expect(
            SpawnedReferenceIdentity.formID(for: .generated(0x00FF_FFFF)) == FormID(0xFFFF_FFFF)
        )
    }

    @Test func pluginKeysAndOverrunSequencesHaveNoSpawnFormID() {
        #expect(SpawnedReferenceIdentity.formID(for: .plugin(name: "a.esm", objectID: 5)) == nil)
        #expect(SpawnedReferenceIdentity.formID(for: .generated(0x0100_0000)) == nil)
    }

    // MARK: - Component invariants

    /// Both normalizations exist because this initializer is also the save
    /// decoder's entry point: a corrupt file has to degrade rather than fail
    /// the whole load.
    @Test func nonPositiveCountsAndScalesNormalize() {
        #expect(Self.spawn(count: 0).count == 1)
        #expect(Self.spawn(count: -7).count == 1)
        #expect(Self.spawn(scale: 0).scale == 1)
        #expect(Self.spawn(scale: .nan).scale == 1)
        #expect(Self.spawn(scale: 2.5).scale == 2.5)
    }

    @Test func componentErasesAndNarrowsBackToItself() {
        let value = Self.spawn(count: 4)
        #expect(ReferenceSpawnState(erased: value.erased) == value)
        #expect(ReferenceSpawnState(erased: ReferenceDeletionState.deleted.erased) == nil)
        #expect(value.erased.kind == .spawn)
    }

    // MARK: - Save round trip

    @MainActor
    private func storeWithOneSpawn() -> (store: WorldStateStore, key: ReferenceKey) {
        let store = WorldStateStore()
        let key = store.allocateGeneratedKey()
        store.set(Self.spawn(count: 6), for: key, in: Self.cell)
        return (store, key)
    }

    @MainActor
    @Test func spawnSurvivesASaveRoundTrip() throws {
        let (store, key) = storeWithOneSpawn()
        let data = OpenSkySaveEncoder.encode(
            snapshot: store.snapshot(), fingerprint: [], metadata: Self.metadata()
        )
        let file = try OpenSkySaveDecoder.decode(data)

        let restored = WorldStateStore()
        restored.restore(from: file.snapshot)
        let spawn = try #require(restored.component(ReferenceSpawnState.self, for: key))
        #expect(spawn == Self.spawn(count: 6))
        #expect(restored.nextGeneratedSequence == store.nextGeneratedSequence)
        #expect(file.snapshot == store.snapshot())
    }

    /// A spawned object usually has no other component, so it writes no `RDLT`
    /// entry at all — which is exactly what lets a build that predates this
    /// chunk load the same save and simply not see the dropped items.
    @MainActor
    @Test func spawnOnlyOwnersWriteNoReferenceDeltaEntry() {
        let (store, _) = storeWithOneSpawn()
        let data = OpenSkySaveEncoder.encode(
            snapshot: store.snapshot(), fingerprint: [], metadata: Self.metadata()
        )
        #expect(Self.chunkPayloadCount(in: data, tag: OpenSkySaveFormat.ChunkTag.referenceDeltas)
            == 0)
        #expect(Self.chunkPayloadCount(in: data, tag: OpenSkySaveFormat.ChunkTag.spawnedReferences)
            == 1)
    }

    /// A spawn that has also been moved or hidden keeps both halves, merged
    /// back into one delta by key rather than by position.
    @MainActor
    @Test func spawnMergesWithTheOwnersOtherComponents() throws {
        let (store, key) = storeWithOneSpawn()
        store.set(ReferenceEnableState.disabled, for: key, in: Self.cell)
        let data = OpenSkySaveEncoder.encode(
            snapshot: store.snapshot(), fingerprint: [], metadata: Self.metadata()
        )
        let file = try OpenSkySaveDecoder.decode(data)
        let delta = try #require(file.snapshot[key])
        #expect(delta.component(ReferenceSpawnState.self) == Self.spawn(count: 6))
        #expect(delta.component(ReferenceEnableState.self) == .disabled)
        #expect(delta.cell == Self.cell)
    }

    @MainActor
    @Test func interiorSpawnsRoundTripTheirCell() throws {
        let store = WorldStateStore()
        let key = store.allocateGeneratedKey()
        store.set(Self.spawn(location: Self.interior), for: key, in: Self.interior)
        let file = try OpenSkySaveDecoder.decode(OpenSkySaveEncoder.encode(
            snapshot: store.snapshot(), fingerprint: [], metadata: Self.metadata()
        ))
        let spawn = try #require(file.snapshot[key]?.component(ReferenceSpawnState.self))
        #expect(spawn.location == Self.interior)
    }

    /// An object with no cell is not in the world, so the decoder refuses to
    /// invent one rather than dropping the item somewhere the player never was.
    @Test func aSpawnEntryWithoutACellIsRejected() {
        var payload = BinaryWriter()
        payload.writeUInt32(1)
        OpenSkySaveEncoder.writeKey(.generated(4), into: &payload)
        payload.writeUInt32(0x100)
        OpenSkySaveEncoder.writeCell(nil, into: &payload)
        for _ in 0 ..< 7 {
            payload.writeFloat32(0)
        }
        payload.writeUInt32(1)
        #expect(throws: (any Error).self) {
            try OpenSkySaveSpawnDecoder.decodeSpawns(payload.data)
        }
    }

    /// A declared entry count far past the bytes available is a thrown error
    /// rather than a multi-gigabyte reservation.
    @Test func aCorruptSpawnCountIsRejectedBeforeAnythingIsReserved() {
        var payload = BinaryWriter()
        payload.writeUInt32(.max)
        #expect(throws: (any Error).self) {
            try OpenSkySaveSpawnDecoder.decodeSpawns(payload.data)
        }
    }

    // MARK: - Chunk inspection

    /// The four-byte element count at the head of a chunk's payload, or nil
    /// when the file carries no such chunk. Walks the chunk stream the same way
    /// the decoder does, so it also proves the chunk is length-delimited.
    private static func chunkPayloadCount(in data: Data, tag: String) -> UInt32? {
        var reader = SaveReader(data)
        guard
            (try? reader.bytes(OpenSkySaveFormat.magic.count, "magic")) != nil,
            (try? reader.uint32("version")) != nil,
            let metadataLength = try? Int(reader.uint32("metadata length")),
            (try? reader.bytes(metadataLength, "metadata")) != nil,
            let plugins = try? reader.uint32("fingerprint count"),
            plugins == 0
        else { return nil }
        while !reader.isAtEnd {
            guard
                let tagBytes = try? reader.bytes(4, "chunk tag"),
                let length = try? Int(reader.uint32("chunk length")),
                let payload = try? reader.bytes(length, "chunk payload")
            else { return nil }
            guard String(bytes: tagBytes, encoding: .utf8) == tag else { continue }
            var payloadReader = SaveReader(payload)
            return try? payloadReader.uint32("entry count")
        }
        return nil
    }
}
