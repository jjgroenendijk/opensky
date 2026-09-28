// QSTS chunk tests (issue #182): the additive quest-state chunk in the OpenSky
// native save container.
//
// Beyond the round trip, two properties matter and mirror what `INVN` promises.
// A save carrying quest state must still load in a build that knows nothing
// about the chunk, which the "older build" case simulates by renaming the tag;
// and `RDLT` must gain nothing, so a quest — which carries no other component —
// leaves no entry there for an older build to restore as an empty reference.

import Foundation
@testable import opensky
import Testing

@MainActor
struct QuestSaveTests {
    private let mainQuest = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0003_5EE4)
    private let sideQuest = ReferenceKey.plugin(name: "dawnguard.esm", objectID: 0x0001_00FF)

    private func started() -> QuestRuntimeState {
        QuestRuntimeState(
            isRunning: true,
            isCompleted: true,
            stagesReached: [10, 20, 200],
            objectives: [
                QuestObjectiveState(index: 20, isCompleted: true),
                QuestObjectiveState(index: 10, isDisplayed: true, isFailed: true)
            ]
        )
    }

    /// A snapshot with three shapes: a quest whose only delta is its state, a
    /// second quest, and an ordinary reference with no quest state at all.
    private func snapshot() -> WorldStateSnapshot {
        let entries = [
            OpenSkySaveFixture.entry(key: mainQuest, cell: nil, components: [started().erased]),
            OpenSkySaveFixture.entry(
                key: sideQuest,
                cell: nil,
                components: [QuestRuntimeState(isRunning: true, stagesReached: [5]).erased]
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

    @Test func questStateSurvivesAnEncodeAndDecode() throws {
        let original = snapshot()
        let file = try OpenSkySaveDecoder.decode(encode(original))
        #expect(file.snapshot == original)

        let delta = try #require(file.snapshot[mainQuest])
        #expect(delta.sortedKinds == [.quest])
        let decoded = try #require(delta.component(QuestRuntimeState.self))
        #expect(decoded == started())
        #expect(decoded.currentStage == 200)
        #expect(decoded.isStageDone(20))
        #expect(!decoded.isStageDone(30))
        #expect(decoded.objective(10).isDisplayed)
        #expect(decoded.objective(10).isFailed)
        #expect(!decoded.objective(10).isCompleted)
        #expect(decoded.objective(20).isCompleted)
    }

    @Test func decodedEntriesStayInReferenceKeyOrder() throws {
        let file = try OpenSkySaveDecoder.decode(encode(snapshot()))
        #expect(file.snapshot.keys == file.snapshot.keys.sorted())
    }

    /// Restoring a decoded save into a live store puts the quests back where
    /// they were, which is the property a loaded game depends on.
    @Test func restoringASaveBringsQuestStateBack() throws {
        let file = try OpenSkySaveDecoder.decode(encode(snapshot()))
        let store = WorldStateStore()
        store.restore(from: file.snapshot)
        #expect(store.dirtyCount == 3)
        #expect(store.component(QuestRuntimeState.self, for: mainQuest) == started())
        #expect(store.snapshot() == file.snapshot)
    }

    /// Two stores that reached the same end state in different orders write
    /// identical bytes, because the component sorts its stages and objectives.
    @Test func encodingIsDeterministicAcrossMutationOrder() {
        let ascending = QuestRuntimeState(
            isRunning: true,
            stagesReached: [10, 20],
            objectives: [
                QuestObjectiveState(index: 10, isDisplayed: true),
                QuestObjectiveState(index: 20, isCompleted: true)
            ]
        )
        let descending = QuestRuntimeState(
            isRunning: true,
            stagesReached: [20, 10],
            objectives: [
                QuestObjectiveState(index: 20, isCompleted: true),
                QuestObjectiveState(index: 10, isDisplayed: true)
            ]
        )
        #expect(encode(single(ascending)) == encode(single(descending)))
    }

    private func single(_ state: QuestRuntimeState) -> WorldStateSnapshot {
        WorldStateSnapshot(
            entries: [OpenSkySaveFixture.entry(
                key: mainQuest, cell: nil, components: [state.erased]
            )],
            nextGeneratedSequence: 1
        )
    }

    // MARK: - Additive-chunk tolerance

    /// A session that touched no quest writes no `QSTS` chunk at all, so its
    /// bytes are the ones this encoder produced before the chunk existed.
    @Test func aSaveWithNoQuestStateCarriesNoChunk() {
        let encoded = encode(OpenSkySaveFixture.richSnapshot())
        #expect(OpenSkySaveFixture.offset(
            ofChunk: OpenSkySaveFormat.ChunkTag.questStates, in: encoded
        ) == nil)
    }

    /// The older-build case: the same file with the chunk tag renamed to one
    /// nothing knows decodes cleanly, losing only the quest state. That is what
    /// "additive, no version bump" buys.
    @Test func anUnknownChunkTagIsSkippedByItsLength() throws {
        let encoded = encode(snapshot())
        let offset = try #require(OpenSkySaveFixture.offset(
            ofChunk: OpenSkySaveFormat.ChunkTag.questStates, in: encoded
        ))
        let renamed = OpenSkySaveFixture.patching(
            encoded, at: offset, with: Array("ZZZZ".utf8)
        )
        let file = try OpenSkySaveDecoder.decode(renamed)
        #expect(file.formatVersion == OpenSkySaveFormat.currentVersion)
        #expect(file.snapshot.nextGeneratedSequence == 3)
        // The quests had no other component, so nothing of them is left — which
        // is exactly the world an older build should restore.
        #expect(file.snapshot[mainQuest] == nil)
        #expect(file.snapshot[sideQuest] == nil)
        #expect(file.snapshot.dirtyCount == 1)
    }

    /// The reverse direction: a file written before the chunk existed loads
    /// with every quest reading from plugin data again.
    @Test func aFileWithNoQuestChunkLoadsCleanly() throws {
        let file = try OpenSkySaveDecoder.decode(OpenSkySaveFixture.file(chunks: [
            OpenSkySaveFixture.allocatorChunk(4),
            OpenSkySaveFixture.deltasChunk(count: 0)
        ]))
        #expect(file.snapshot.entries.isEmpty)
        #expect(file.snapshot.nextGeneratedSequence == 4)
    }

    // MARK: - Corruption

    /// Quest state is not an `RDLT` component kind, so a file claiming
    /// otherwise is rejected rather than half read.
    @Test func rdltRejectsAQuestComponentTag() throws {
        let payload = OpenSkySaveFixture.entriesPayload(
            count: 1,
            entries: OpenSkySaveFixture.entryBytes(
                componentCount: 1, components: OpenSkySaveFixture.bytes([6, 0])
            )
        )
        #expect(throws: OpenSkySaveError.self) {
            try OpenSkySaveDecoder.decode(
                OpenSkySaveFixture.file(chunks: [OpenSkySaveFixture.chunk("RDLT", payload)])
            )
        }
    }

    /// A declared entry count that cannot fit in the bytes left is refused
    /// before anything is reserved, the same bounds rule every chunk follows.
    @Test func animpossibleEntryCountIsRejected() throws {
        var payload = BinaryWriter()
        payload.writeUInt32(0xFFFF_FFFF)
        #expect(throws: OpenSkySaveError.self) {
            try OpenSkySaveQuestDecoder.decodeQuestStates(payload.data)
        }
    }

    /// So is an impossible stage count inside an otherwise valid entry.
    @Test func anImpossibleStageCountIsRejected() throws {
        var payload = BinaryWriter()
        payload.writeUInt32(1)
        OpenSkySaveEncoder.writeKey(mainQuest, into: &payload)
        payload.writeUInt8(OpenSkySaveFormat.QuestFlag.running)
        payload.writeUInt32(0x00FF_FFFF)
        #expect(throws: OpenSkySaveError.self) {
            try OpenSkySaveQuestDecoder.decodeQuestStates(payload.data)
        }
    }

    /// Unknown bits in an objective's flag byte are ignored rather than
    /// refused, so a chunk a newer build wrote still restores what this build
    /// understands.
    @Test func unknownObjectiveFlagBitsAreIgnored() throws {
        var payload = BinaryWriter()
        payload.writeUInt32(1)
        OpenSkySaveEncoder.writeKey(mainQuest, into: &payload)
        payload.writeUInt8(OpenSkySaveFormat.QuestFlag.running)
        payload.writeUInt32(0)
        payload.writeUInt32(1)
        payload.writeUInt16(7)
        payload.writeUInt8(0xFF)
        let entries = try OpenSkySaveQuestDecoder.decodeQuestStates(payload.data)
        let state = try #require(entries.first?.state)
        #expect(state.isRunning)
        #expect(state.objective(7).isDisplayed)
        #expect(state.objective(7).isCompleted)
        #expect(state.objective(7).isFailed)
    }
}
