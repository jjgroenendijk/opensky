// AVAL chunk tests (issue #194): the additive actor-value chunk in the OpenSky
// native save container.
//
// Beyond the round trip, the properties that matter mirror what `INVN` and
// `QSTS` promise. A save carrying actor values must still load in a build that
// knows nothing about the chunk, which the "older build" case simulates by
// renaming the tag; and `RDLT` must gain nothing, so an actor whose only
// component is its values leaves no entry there for an older build to restore
// as an empty reference.

import Foundation
@testable import opensky
import Testing

@MainActor
struct ActorValueSaveTests {
    private let wounded = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0001_3BAC)
    private let player = ReferenceKey.player

    private func hurt() -> ActorValueState {
        ActorValueState(current: ActorValues(health: 62.5, magicka: 0, stamina: 149.75))
    }

    /// A snapshot with three shapes: an actor whose only delta is its values
    /// and which belongs to a cell, the player (a generated key, no cell), and
    /// an ordinary reference with no actor values at all.
    private func snapshot() -> WorldStateSnapshot {
        let entries = [
            OpenSkySaveFixture.entry(
                key: wounded,
                cell: OpenSkySaveFixture.whiterun,
                components: [hurt().erased]
            ),
            OpenSkySaveFixture.entry(
                key: player,
                cell: nil,
                components: [
                    ActorValueState(
                        current: ActorValues(health: 100, magicka: 33, stamina: 100)
                    ).erased
                ]
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

    @Test func actorValuesSurviveAnEncodeAndDecode() throws {
        let original = snapshot()
        let file = try OpenSkySaveDecoder.decode(encode(original))
        #expect(file.snapshot == original)

        let delta = try #require(file.snapshot[wounded])
        #expect(delta.sortedKinds == [.actorValues])
        #expect(delta.cell == OpenSkySaveFixture.whiterun)
        #expect(delta.component(ActorValueState.self) == hurt())
    }

    @Test func decodedEntriesStayInReferenceKeyOrder() throws {
        let file = try OpenSkySaveDecoder.decode(encode(snapshot()))
        #expect(file.snapshot.keys == file.snapshot.keys.sorted())
    }

    /// Restoring a decoded save into a live store puts the wounded actors back
    /// where they were, which is the property a loaded game depends on.
    @Test func restoringASaveBringsActorValuesBack() throws {
        let file = try OpenSkySaveDecoder.decode(encode(snapshot()))
        let store = WorldStateStore()
        store.restore(from: file.snapshot)
        #expect(store.dirtyCount == 3)
        #expect(store.component(ActorValueState.self, for: wounded) == hurt())
        #expect(store.snapshot() == file.snapshot)
    }

    /// The maximums are deliberately not written: a restored actor re-derives
    /// them from records, so a session that reads a save built against changed
    /// records gets the records' numbers rather than the save's.
    @Test func theRestoredCurrentValuesClampToTheDerivedMaximums() throws {
        let file = try OpenSkySaveDecoder.decode(encode(snapshot()))
        let store = WorldStateStore()
        store.restore(from: file.snapshot)
        let runtime = ActorValueRuntime(
            store: store,
            baselines: ActorValueBaselineResolver(
                fallback: ActorValueBaseline(
                    maximums: ActorValues(repeating: 50),
                    regenPercentPerSecond: .zero
                )
            )
        )
        let holder = ActorValueHolder(key: wounded, subject: .actor(base: FormID(0x0001_3BAC)))
        // Stored at 149.75, but the records now say 50.
        #expect(runtime.current(of: holder).stamina == 149.75)
        #expect(runtime.fractions(of: holder).stamina == 1)
        #expect(runtime.restore(.stamina, by: 1, on: holder).current.stamina == 50)
    }

    /// Two stores that reached the same end state write identical bytes.
    @Test func encodingIsDeterministic() {
        #expect(encode(snapshot()) == encode(snapshot()))
    }

    // MARK: - AVOV, the override table (issues #468 and #496)

    /// One actor holding two overrides, one of them damaged, and a base
    /// override on a primary.
    private func resistant() -> ActorValueState {
        ActorValueState(
            current: ActorValues(health: 62.5, magicka: 0, stamina: 149.75),
            overrides: [
                ActorValueIndex.resistFire: ActorValueOverride(
                    baseOffset: 40, permanent: 10, temporary: 25, damage: -15
                ),
                15: ActorValueOverride(baseOffset: 22),
                ActorValueIdentity.index(of: .health): ActorValueOverride(baseOffset: 25)
            ]
        )
    }

    private func resistantSnapshot() -> WorldStateSnapshot {
        WorldStateSnapshot(
            entries: [OpenSkySaveFixture.entry(
                key: wounded,
                cell: OpenSkySaveFixture.whiterun,
                components: [resistant().erased]
            )],
            nextGeneratedSequence: 5,
            sequence: 11
        )
    }

    /// The override table survives the round trip — except the temporary
    /// modifier, which is deliberately not written because the magic effect
    /// that established it is what re-establishes it (issue 19.6).
    @Test func actorValueOverridesSurviveAnEncodeAndDecodeWithoutTheTemporarySlot() throws {
        let file = try OpenSkySaveDecoder.decode(encode(resistantSnapshot()))
        let delta = try #require(file.snapshot[wounded])
        let state = try #require(delta.component(ActorValueState.self))
        #expect(state.current == resistant().current)
        #expect(state.overrides[ActorValueIndex.resistFire] == ActorValueOverride(
            baseOffset: 40, permanent: 10, damage: -15
        ))
        #expect(state.overrides[15] == ActorValueOverride(baseOffset: 22))
        // A primary's base override travels in the same table (issue #496).
        #expect(
            state.overrides[ActorValueIdentity.index(of: .health)]
                == ActorValueOverride(baseOffset: 25)
        )
        #expect(state.overrides.count == 3)
    }

    @Test func actorValueOverrideEncodingIsDeterministic() {
        #expect(encode(resistantSnapshot()) == encode(resistantSnapshot()))
    }

    /// A session that moved no value off its baseline writes no `AVOV` chunk,
    /// so its bytes are the ones this encoder produced before the chunk
    /// existed.
    @Test func aSaveWithNoActorValueOverridesCarriesNoChunk() {
        #expect(OpenSkySaveFixture.offset(
            ofChunk: OpenSkySaveFormat.ChunkTag.actorValueOverrides, in: encode(snapshot())
        ) == nil)
    }

    /// The older-build case for `AVOV`: renaming the tag loses the overrides
    /// and keeps everything else, including the actor's health.
    @Test func anUnknownActorValueOverrideChunkTagIsSkipped() throws {
        let encoded = encode(resistantSnapshot())
        let offset = try #require(OpenSkySaveFixture.offset(
            ofChunk: OpenSkySaveFormat.ChunkTag.actorValueOverrides, in: encoded
        ))
        let renamed = OpenSkySaveFixture.patching(
            encoded, at: offset, with: Array("ZZZZ".utf8)
        )
        let file = try OpenSkySaveDecoder.decode(renamed)
        let state = try #require(file.snapshot[wounded]?.component(ActorValueState.self))
        #expect(state.current == resistant().current)
        #expect(state.overrides.isEmpty)
    }

    // MARK: - Additive-chunk tolerance

    /// A session in which nothing took damage writes no `AVAL` chunk at all, so
    /// its bytes are the ones this encoder produced before the chunk existed.
    @Test func aSaveWithNoActorValuesCarriesNoChunk() {
        let encoded = encode(OpenSkySaveFixture.richSnapshot())
        #expect(OpenSkySaveFixture.offset(
            ofChunk: OpenSkySaveFormat.ChunkTag.actorValues, in: encoded
        ) == nil)
    }

    /// The older-build case: the same file with the chunk tag renamed to one
    /// nothing knows decodes cleanly, losing only the actor values. That is
    /// what "additive, no version bump" buys.
    @Test func anUnknownChunkTagIsSkippedByItsLength() throws {
        let encoded = encode(snapshot())
        let offset = try #require(OpenSkySaveFixture.offset(
            ofChunk: OpenSkySaveFormat.ChunkTag.actorValues, in: encoded
        ))
        let renamed = OpenSkySaveFixture.patching(
            encoded, at: offset, with: Array("ZZZZ".utf8)
        )
        let file = try OpenSkySaveDecoder.decode(renamed)
        #expect(file.formatVersion == OpenSkySaveFormat.currentVersion)
        #expect(file.snapshot.nextGeneratedSequence == 5)
        // The actors had no other component, so nothing of them is left — the
        // world an older build should restore, with everyone at full health.
        #expect(file.snapshot[wounded] == nil)
        #expect(file.snapshot[player] == nil)
        #expect(file.snapshot.dirtyCount == 1)
    }

    /// The reverse direction: a file written before the chunk existed loads
    /// with every actor re-deriving a full baseline.
    @Test func aFileWithNoActorValueChunkLoadsCleanly() throws {
        let file = try OpenSkySaveDecoder.decode(OpenSkySaveFixture.file(chunks: [
            OpenSkySaveFixture.allocatorChunk(4),
            OpenSkySaveFixture.deltasChunk(count: 0)
        ]))
        #expect(file.snapshot.entries.isEmpty)
        #expect(file.snapshot.nextGeneratedSequence == 4)
    }

    // MARK: - Corruption

    /// Actor values are not an `RDLT` component kind, so a file claiming
    /// otherwise is rejected rather than half read.
    @Test func rdltRejectsAnActorValueComponentTag() throws {
        let payload = OpenSkySaveFixture.entriesPayload(
            count: 1,
            entries: OpenSkySaveFixture.entryBytes(
                componentCount: 1, components: OpenSkySaveFixture.bytes([8, 0])
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
    @Test func anImpossibleEntryCountIsRejected() throws {
        var payload = BinaryWriter()
        payload.writeUInt32(0xFFFF_FFFF)
        #expect(throws: OpenSkySaveError.self) {
            try OpenSkySaveActorValueDecoder.decodeActorValues(payload.data)
        }
    }

    /// A truncated entry is a thrown error rather than a partial state.
    @Test func aTruncatedEntryIsRejected() throws {
        var payload = BinaryWriter()
        payload.writeUInt32(1)
        payload.writeUInt8(OpenSkySaveFormat.KeyTag.generated)
        payload.writeUInt64(0)
        #expect(throws: OpenSkySaveError.self) {
            try OpenSkySaveActorValueDecoder.decodeActorValues(payload.data)
        }
    }

    /// A NaN or negative value on disk normalizes to zero rather than failing
    /// the load: the invariant belongs to `ActorValueState`, and one nonsensical
    /// float is not a reason to lose a whole save.
    @Test func aCorruptFloatNormalizesRatherThanFailing() throws {
        var payload = BinaryWriter()
        payload.writeUInt32(1)
        payload.writeUInt8(OpenSkySaveFormat.KeyTag.generated)
        payload.writeUInt64(0)
        payload.writeUInt8(OpenSkySaveFormat.CellTag.absent)
        payload.writeFloat32(.nan)
        payload.writeFloat32(-50)
        payload.writeFloat32(25)
        let entries = try OpenSkySaveActorValueDecoder.decodeActorValues(payload.data)
        #expect(entries.count == 1)
        #expect(entries[0].state.current == ActorValues(health: 0, magicka: 0, stamina: 25))
    }
}
