// DLGS chunk tests (issue #426): the additive dialogue said-state chunk in the
// OpenSky native save container.
//
// Beyond the round trip, the same three properties `QuestSaveTests` pins hold
// here and for the same reasons. A save carrying said-state must still load in
// a build that knows nothing about the chunk, which the "older build" case
// simulates by renaming the tag; `RDLT` must gain nothing, so a response —
// which carries no other component — leaves no entry there for an older build
// to restore as an empty reference; and a session in which nobody spoke must
// write the bytes this encoder produced before the chunk existed.

import Foundation
@testable import opensky
import Testing

@MainActor
struct DialogueSaveTests {
    private let spoken = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0000_2004)
    private let repeated = ReferenceKey.plugin(name: "dawnguard.esm", objectID: 0x0001_00FF)

    private func snapshot() -> WorldStateSnapshot {
        let entries = [
            OpenSkySaveFixture.entry(
                key: spoken, cell: nil, components: [DialogueRuntimeState(saidCount: 1).erased]
            ),
            OpenSkySaveFixture.entry(
                key: repeated,
                cell: nil,
                components: [DialogueRuntimeState(saidCount: 7).erased]
            ),
            OpenSkySaveFixture.entry(
                key: .plugin(name: "skyrim.esm", objectID: 1),
                cell: OpenSkySaveFixture.whiterun,
                components: [ReferenceDeletionState.deleted.erased]
            )
        ]
        return WorldStateSnapshot(
            entries: entries.sorted { $0.key < $1.key },
            nextGeneratedSequence: 3,
            sequence: 42
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

    @Test func saidStateSurvivesAnEncodeAndDecode() throws {
        let original = snapshot()
        let file = try OpenSkySaveDecoder.decode(encode(original))
        #expect(file.snapshot == original)

        let delta = try #require(file.snapshot[spoken])
        #expect(delta.sortedKinds == [.dialogue])
        let decoded = try #require(delta.component(DialogueRuntimeState.self))
        #expect(decoded.saidCount == 1)
        #expect(decoded.hasBeenSaid)
        #expect(file.snapshot[repeated]?.component(DialogueRuntimeState.self)?.saidCount == 7)
    }

    @Test func decodedEntriesStayInReferenceKeyOrder() throws {
        let file = try OpenSkySaveDecoder.decode(encode(snapshot()))
        #expect(file.snapshot.keys == file.snapshot.keys.sorted())
    }

    /// The property a loaded game depends on, end to end: a say-once response
    /// said before the save is still spent after it.
    @Test func aSayOnceResponseStaysSpentAcrossASaveRoundTrip() throws {
        let store = WorldStateStore()
        let runtime = try DialogueRuntimeFixture.runtime(store: store)
        let id = FormID(DialogueRuntimeFixture.urgentFirstInfo)
        try runtime.choose(id, speaker: DialogueRuntimeFixture.speakerKey)

        let file = try OpenSkySaveDecoder.decode(encode(store.snapshot()))
        let restored = WorldStateStore()
        restored.restore(from: file.snapshot)
        let reloaded = try DialogueRuntimeFixture.runtime(store: restored)

        #expect(reloaded.hasBeenSaid(id))
        let offer = try #require(reloaded.topics(for: DialogueRuntimeFixture.speakerKey)
            .offers.first { $0.topic.rawValue == DialogueRuntimeFixture.urgentTopic })
        #expect(offer.info.rawValue == DialogueRuntimeFixture.urgentSecondInfo)
    }

    // MARK: - Additive-chunk tolerance

    /// A session in which nobody spoke writes no `DLGS` chunk at all.
    @Test func aSaveWithNoSaidStateCarriesNoChunk() {
        let encoded = encode(OpenSkySaveFixture.richSnapshot())
        #expect(OpenSkySaveFixture.offset(
            ofChunk: OpenSkySaveFormat.ChunkTag.dialogueStates, in: encoded
        ) == nil)
    }

    /// The older-build case: the same file with the chunk tag renamed to one
    /// nothing knows decodes cleanly, losing only the said-state.
    @Test func anUnknownChunkTagIsSkippedByItsLength() throws {
        let encoded = encode(snapshot())
        let offset = try #require(OpenSkySaveFixture.offset(
            ofChunk: OpenSkySaveFormat.ChunkTag.dialogueStates, in: encoded
        ))
        let renamed = OpenSkySaveFixture.patching(
            encoded, at: offset, with: Array("ZZZZ".utf8)
        )
        let file = try OpenSkySaveDecoder.decode(renamed)
        #expect(file.snapshot[spoken] == nil)
        #expect(file.snapshot[repeated] == nil)
        #expect(file.snapshot.dirtyCount == 1)
    }

    // MARK: - Corruption

    /// Said-state is not an `RDLT` component kind, so a file claiming otherwise
    /// is rejected rather than half read.
    @Test func rdltRejectsADialogueComponentTag() throws {
        let payload = OpenSkySaveFixture.entriesPayload(
            count: 1,
            entries: OpenSkySaveFixture.entryBytes(
                componentCount: 1, components: OpenSkySaveFixture.bytes([11, 0])
            )
        )
        #expect(throws: OpenSkySaveError.self) {
            try OpenSkySaveDecoder.decode(
                OpenSkySaveFixture.file(chunks: [OpenSkySaveFixture.chunk("RDLT", payload)])
            )
        }
    }

    /// A declared entry count that cannot fit in the bytes left is refused
    /// before anything is reserved.
    @Test func anImpossibleEntryCountIsRejected() throws {
        var payload = BinaryWriter()
        payload.writeUInt32(0xFFFF_FFFF)
        #expect(throws: OpenSkySaveError.self) {
            try OpenSkySaveDialogueDecoder.decodeDialogueStates(payload.data)
        }
    }

    /// A zero count is the untouched baseline, which the encoder never writes.
    /// One arriving from a hand-built file is dropped rather than stored, so a
    /// restored world still compares equal to a world that never spoke.
    @Test func aZeroSaidCountRestoresNoComponent() throws {
        var payload = BinaryWriter()
        payload.writeUInt32(1)
        OpenSkySaveEncoder.writeKey(spoken, into: &payload)
        payload.writeUInt32(0)
        let entries = try OpenSkySaveDialogueDecoder.decodeDialogueStates(payload.data)
        #expect(entries.count == 1)
        #expect(OpenSkySaveDialogueDecoder.merge(entries, into: []).isEmpty)
    }
}
