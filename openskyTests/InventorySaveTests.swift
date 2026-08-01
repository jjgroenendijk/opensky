// INVN chunk tests (issue #176): the additive inventory chunk in the OpenSky
// native save container.
//
// Two properties matter beyond the round trip. First, a save carrying
// inventory must still be readable by a build that knows nothing about the
// chunk, which is what the "older build" case simulates by decoding with the
// tag renamed. Second, `RDLT` must not gain anything: an owner whose only
// delta is its inventory writes no `RDLT` entry at all, so the bytes an older
// build sees are exactly the ones it would have written itself.

import Foundation
@testable import opensky
import simd
import Testing

@MainActor
struct InventorySaveTests {
    private let gold = FormID(0x0000_000F)
    private let sword = FormID(0x0001_2EB7)
    private let helmet = FormID(0x0001_3960)

    private let whiterun = CellSceneLocation.exterior(CellCoordinate(x: -12, y: -3))
    private let inn = CellSceneLocation.interior(FormID(0xDEAD_BEEF))

    private func chestKey() -> ReferenceKey {
        .plugin(name: "skyrim.esm", objectID: 0x0BAD)
    }

    private func inventory(gold count: Int32 = 25) -> ReferenceInventoryState {
        ReferenceInventoryState(
            stacks: [
                InventoryStack(item: sword, count: 1),
                InventoryStack(item: gold, count: count),
                InventoryStack(item: helmet, count: 2)
            ],
            equipped: [helmet, sword]
        )
    }

    /// A snapshot with three shapes: an owner carrying inventory alongside
    /// other components, an owner whose only delta is its inventory, and an
    /// owner with no inventory at all.
    private func snapshot() -> WorldStateSnapshot {
        let entries = [
            OpenSkySaveFixture.entry(
                key: chestKey(),
                cell: whiterun,
                components: [
                    ReferenceEnableState.disabled.erased,
                    inventory().erased
                ]
            ),
            OpenSkySaveFixture.entry(
                key: .generated(9),
                cell: inn,
                components: [ReferenceInventoryState(
                    stacks: [InventoryStack(item: gold, count: 7)]
                ).erased]
            ),
            OpenSkySaveFixture.entry(
                key: .plugin(name: "skyrim.esm", objectID: 1),
                cell: nil,
                components: [ReferenceDeletionState.deleted.erased]
            )
        ]
        return WorldStateSnapshot(
            entries: entries.sorted { $0.key < $1.key },
            nextGeneratedSequence: 12,
            sequence: 99
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

    @Test func inventoriesSurviveAnEncodeAndDecode() throws {
        let original = snapshot()
        let file = try OpenSkySaveDecoder.decode(encode(original))
        #expect(file.snapshot == original)

        let delta = try #require(file.snapshot[chestKey()])
        #expect(delta.cell == whiterun)
        #expect(delta.sortedKinds == [.enableState, .inventory])
        let decoded = try #require(delta.component(ReferenceInventoryState.self))
        #expect(decoded == inventory())
        #expect(decoded.equipped == [sword, helmet])
        #expect(decoded.count(of: gold) == 25)
    }

    /// An owner whose only delta is its inventory keeps its cell, which is why
    /// the INVN entry carries one rather than referring back to RDLT.
    @Test func inventoryOnlyOwnerKeepsItsCellAndItsItems() throws {
        let file = try OpenSkySaveDecoder.decode(encode(snapshot()))
        let delta = try #require(file.snapshot[.generated(9)])
        #expect(delta.cell == inn)
        #expect(delta.sortedKinds == [.inventory])
        #expect(delta.component(ReferenceInventoryState.self)?.count(of: gold) == 7)
    }

    @Test func decodedEntriesStayInReferenceKeyOrder() throws {
        let file = try OpenSkySaveDecoder.decode(encode(snapshot()))
        #expect(file.snapshot.keys == file.snapshot.keys.sorted())
    }

    /// Restoring a decoded save into a live store puts the inventories back
    /// where they were, which is the property a loaded game depends on.
    @Test func restoringASaveBringsInventoriesBack() throws {
        let file = try OpenSkySaveDecoder.decode(encode(snapshot()))
        let store = WorldStateStore()
        store.restore(from: file.snapshot)
        #expect(store.dirtyCount == 3)
        #expect(
            store.component(ReferenceInventoryState.self, for: chestKey()) == inventory()
        )
        #expect(store.snapshot() == file.snapshot)
    }

    @Test func encodingIsDeterministicAcrossMutationOrder() {
        let ascending = ReferenceInventoryState(stacks: [
            InventoryStack(item: gold, count: 1),
            InventoryStack(item: sword, count: 1)
        ])
        let descending = ReferenceInventoryState(stacks: [
            InventoryStack(item: sword, count: 1),
            InventoryStack(item: gold, count: 1)
        ])
        let first = WorldStateSnapshot(
            entries: [OpenSkySaveFixture.entry(
                key: chestKey(), cell: whiterun, components: [ascending.erased]
            )],
            nextGeneratedSequence: 1
        )
        let second = WorldStateSnapshot(
            entries: [OpenSkySaveFixture.entry(
                key: chestKey(), cell: whiterun, components: [descending.erased]
            )],
            nextGeneratedSequence: 1
        )
        #expect(encode(first) == encode(second))
    }

    // MARK: - Additive-chunk tolerance

    /// A session that touched no inventory writes no `INVN` chunk at all, so
    /// its bytes are the ones this encoder produced before the chunk existed.
    @Test func aSaveWithNoInventoryCarriesNoChunk() {
        let encoded = encode(OpenSkySaveFixture.richSnapshot())
        #expect(OpenSkySaveFixture.offset(
            ofChunk: OpenSkySaveFormat.ChunkTag.inventories, in: encoded
        ) == nil)
    }

    /// The older-build case: the same file with the chunk tag renamed to one
    /// nothing knows decodes cleanly, losing only the inventories. That is what
    /// "additive, no version bump" buys.
    @Test func anUnknownChunkTagIsSkippedByItsLength() throws {
        let encoded = encode(snapshot())
        let offset = try #require(OpenSkySaveFixture.offset(
            ofChunk: OpenSkySaveFormat.ChunkTag.inventories, in: encoded
        ))
        let renamed = OpenSkySaveFixture.patching(
            encoded, at: offset, with: Array("ZZZZ".utf8)
        )
        let file = try OpenSkySaveDecoder.decode(renamed)
        // Everything that was not inventory came through untouched.
        #expect(file.formatVersion == OpenSkySaveFormat.currentVersion)
        #expect(file.snapshot.nextGeneratedSequence == 12)
        #expect(file.snapshot[chestKey()]?.sortedKinds == [.enableState])
        #expect(file.snapshot[.plugin(name: "skyrim.esm", objectID: 1)]?.sortedKinds == [.deletion])
        // The owner that had nothing but an inventory has no entry left, which
        // is exactly the state an older build should restore.
        #expect(file.snapshot[.generated(9)] == nil)
        #expect(file.snapshot.dirtyCount == 2)
    }

    /// The reverse direction: a file written before the chunk existed loads
    /// with every owner reading from plugin data again.
    @Test func aFileWithNoInventoryChunkLoadsCleanly() throws {
        let file = try OpenSkySaveDecoder.decode(OpenSkySaveFixture.file(chunks: [
            OpenSkySaveFixture.allocatorChunk(5),
            OpenSkySaveFixture.deltasChunk(count: 0)
        ]))
        #expect(file.snapshot.entries.isEmpty)
        #expect(file.snapshot.nextGeneratedSequence == 5)
    }

    /// Inventory is not an `RDLT` component kind, and tag 4 stays unknown
    /// there, so a file claiming otherwise is rejected rather than half read.
    @Test func rdltRejectsAnInventoryComponentTag() throws {
        let payload = OpenSkySaveFixture.entriesPayload(
            count: 1,
            entries: OpenSkySaveFixture.entryBytes(
                componentCount: 1, components: OpenSkySaveFixture.bytes([4, 0])
            )
        )
        let data = OpenSkySaveFixture.file(chunks: [
            OpenSkySaveFixture.chunk(OpenSkySaveFormat.ChunkTag.referenceDeltas, payload)
        ])
        #expect(throws: OpenSkySaveError.self) {
            try OpenSkySaveDecoder.decode(data)
        }
    }

    // MARK: - Defensive decoding

    @Test func anImpossibleEntryCountIsRejectedBeforeAnythingIsReserved() throws {
        let data = OpenSkySaveFixture.file(chunks: [
            OpenSkySaveFixture.chunk(
                OpenSkySaveFormat.ChunkTag.inventories,
                countOnlyPayload(.max)
            )
        ])
        #expect(throws: OpenSkySaveError.self) {
            try OpenSkySaveDecoder.decode(data)
        }
    }

    @Test func anImpossibleStackCountIsRejected() throws {
        var writer = BinaryWriter()
        writer.writeUInt32(1)
        writer.write(OpenSkySaveFixture.pluginKeyBytes())
        writer.writeUInt8(OpenSkySaveFormat.CellTag.absent)
        writer.writeUInt32(.max)
        let data = OpenSkySaveFixture.file(chunks: [
            OpenSkySaveFixture.chunk(OpenSkySaveFormat.ChunkTag.inventories, writer.data)
        ])
        #expect(throws: OpenSkySaveError.self) {
            try OpenSkySaveDecoder.decode(data)
        }
    }

    @Test func anImpossibleEquippedCountIsRejected() throws {
        var writer = BinaryWriter()
        writer.writeUInt32(1)
        writer.write(OpenSkySaveFixture.pluginKeyBytes())
        writer.writeUInt8(OpenSkySaveFormat.CellTag.absent)
        writer.writeUInt32(0)
        writer.writeUInt32(.max)
        let data = OpenSkySaveFixture.file(chunks: [
            OpenSkySaveFixture.chunk(OpenSkySaveFormat.ChunkTag.inventories, writer.data)
        ])
        #expect(throws: OpenSkySaveError.self) {
            try OpenSkySaveDecoder.decode(data)
        }
    }

    /// A truncated entry is a thrown error rather than a partial inventory.
    @Test func aTruncatedEntryIsRejected() throws {
        let encoded = encode(snapshot())
        let offset = try #require(OpenSkySaveFixture.offset(
            ofChunk: OpenSkySaveFormat.ChunkTag.inventories, in: encoded
        ))
        #expect(throws: OpenSkySaveError.self) {
            try OpenSkySaveDecoder.decode(
                OpenSkySaveFixture.truncating(encoded, to: offset + 12)
            )
        }
    }

    /// A saved stack whose count is zero or negative is dropped by the
    /// component's own invariant instead of failing the load: one nonsensical
    /// stack is not a reason to lose a whole save.
    @Test func aNonPositiveSavedStackIsDroppedRatherThanRejected() throws {
        var writer = BinaryWriter()
        writer.writeUInt32(1)
        writer.write(OpenSkySaveFixture.pluginKeyBytes())
        writer.writeUInt8(OpenSkySaveFormat.CellTag.absent)
        writer.writeUInt32(2)
        writer.writeUInt32(gold.rawValue)
        writer.writeUInt32(UInt32(bitPattern: Int32(-3)))
        writer.writeUInt32(sword.rawValue)
        writer.writeUInt32(4)
        writer.writeUInt32(0)
        let data = OpenSkySaveFixture.file(chunks: [
            OpenSkySaveFixture.chunk(OpenSkySaveFormat.ChunkTag.inventories, writer.data)
        ])
        let file = try OpenSkySaveDecoder.decode(data)
        let key = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0BAD)
        let decoded = try #require(
            file.snapshot[key]?.component(ReferenceInventoryState.self)
        )
        #expect(decoded.stacks == [InventoryStack(item: sword, count: 4)])
    }

    private func countOnlyPayload(_ count: UInt32) -> Data {
        var writer = BinaryWriter()
        writer.writeUInt32(count)
        return writer.data
    }
}
