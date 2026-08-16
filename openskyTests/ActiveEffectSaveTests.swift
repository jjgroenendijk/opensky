// The AEFF save chunk (issue #469, roadmap item 19.6): round trip, additivity
// and the tolerance rules the container promises.
//
// A save is OpenSky's own format, so nothing here touches game data at all.

import Foundation
@testable import opensky
import Testing

struct ActiveEffectSaveTests {
    private let actor = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0001_3BAC)
    private let potion = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0003_EADE)
    private let mgef = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0003_EB24)
    private let keyword = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0009_0000)

    private func effect(
        sequence: UInt64 = 1,
        mode: ActiveEffectMode = .modifier,
        elapsed: Float = 4,
        caster: ReferenceKey? = nil,
        stackKeyword: ReferenceKey? = nil
    ) -> ActiveEffect {
        ActiveEffect(
            sequence: sequence,
            source: ActiveEffectSource(kind: .potion, record: potion),
            effect: mgef,
            caster: caster,
            mode: mode,
            isDetrimental: false,
            duration: 60,
            elapsed: elapsed,
            paidSeconds: mode == .perSecond ? 4 : 0,
            values: [
                ActiveEffectValue(index: 41, magnitude: 20, applied: 20),
                ActiveEffectValue(index: 43, magnitude: 10, applied: 10)
            ],
            stackKeyword: stackKeyword
        )
    }

    private func snapshot(_ state: ActiveEffectState) -> WorldStateSnapshot {
        WorldStateSnapshot(
            entries: [
                OpenSkySaveFixture.entry(
                    key: actor,
                    cell: OpenSkySaveFixture.whiterun,
                    components: [state.erased]
                )
            ],
            nextGeneratedSequence: 1,
            sequence: 1
        )
    }

    private func roundTrip(_ state: ActiveEffectState) throws -> ActiveEffectState? {
        let data = OpenSkySaveEncoder.encode(
            snapshot: snapshot(state),
            fingerprint: OpenSkySaveFixture.fingerprint,
            metadata: OpenSkySaveFixture.metadata
        )
        let file = try OpenSkySaveDecoder.decode(data)
        return file.snapshot.entries
            .first { $0.key == actor }?
            .delta.component(ActiveEffectState.self)
    }

    /// Everything an effect carries survives the trip, including the modifier
    /// amounts the actor-value chunk deliberately does not persist.
    @Test func everyFieldSurvivesARoundTrip() throws {
        let state = ActiveEffectState(effects: [
            effect(sequence: 1, caster: .player, stackKeyword: keyword),
            effect(sequence: 2, mode: .perSecond)
        ])
        let restored = try #require(try roundTrip(state))
        #expect(restored == state)
        #expect(restored.effects[0].caster == ReferenceKey.player)
        #expect(restored.effects[0].stackKeyword == keyword)
        #expect(restored.effects[1].mode == .perSecond)
        #expect(restored.effects[1].paidSeconds == 4)
        #expect(restored.ownedModifiers == [41: 40, 43: 20])
    }

    /// The chunk is what makes the dropped temporary modifier recoverable: the
    /// restored effects still say what each of them owns.
    @Test func restoredEffectsCarryTheModifiersTheyOwn() throws {
        let restored = try #require(try roundTrip(ActiveEffectState(effects: [effect()])))
        #expect(restored.ownedModifiers[41] == 20)
        #expect(restored.effects[0].remaining == 56)
    }

    /// A session in which nothing was applied writes no chunk at all, so the
    /// bytes match what the encoder produced before the chunk existed.
    @Test func aSessionWithNoEffectsWritesNoChunk() {
        let data = OpenSkySaveEncoder.encode(
            snapshot: OpenSkySaveFixture.richSnapshot(),
            fingerprint: OpenSkySaveFixture.fingerprint,
            metadata: OpenSkySaveFixture.metadata
        )
        #expect(!data.contains(Data(OpenSkySaveFormat.ChunkTag.activeEffects.utf8)))
    }

    /// An effect with a zero duration or no values is corruption rather than an
    /// instantaneous effect, and is normalized away rather than failing a load.
    @Test func degenerateEffectsAreDroppedRatherThanLoaded() {
        let state = ActiveEffectState(effects: [
            ActiveEffect(
                sequence: 1,
                source: ActiveEffectSource(kind: .potion, record: potion),
                effect: mgef,
                mode: .modifier,
                isDetrimental: false,
                duration: 0,
                values: [ActiveEffectValue(index: 41, magnitude: 5)]
            ),
            ActiveEffect(
                sequence: 2,
                source: ActiveEffectSource(kind: .potion, record: potion),
                effect: mgef,
                mode: .modifier,
                isDetrimental: false,
                duration: 10,
                values: []
            )
        ])
        #expect(state.isEmpty)
    }

    /// An unknown source kind is the one hard stop: the byte is one this build
    /// wrote itself, so an unreadable one means the file is not what it claims.
    @Test func anUnknownSourceKindFailsTheLoad() throws {
        var data = try #require(
            OpenSkySaveEncoder.encode(
                snapshot: snapshot(ActiveEffectState(effects: [effect()])),
                fingerprint: OpenSkySaveFixture.fingerprint,
                metadata: OpenSkySaveFixture.metadata
            ) as Data?
        )
        let tag = Data(OpenSkySaveFormat.ChunkTag.activeEffects.utf8)
        let start = try #require(data.range(of: tag)?.upperBound)
        // Chunk length (4) + entry count (4) + key tag (1) + name length (2) +
        // name (10) + objectID (4) + cell tag (1) + coordinates (8) + effect
        // count (4) + sequence (8) lands on the source-kind word.
        let kindOffset = start + 4 + 4 + 1 + 2 + 10 + 4 + 1 + 8 + 4 + 8
        data[kindOffset] = 0x7F
        #expect(throws: OpenSkySaveError.self) {
            try OpenSkySaveDecoder.decode(data)
        }
    }
}
