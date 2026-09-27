// PTMR chunk coverage for the OpenSky native save container (issue #277):
// pending update-timer slots round-trip, bytes stay deterministic, an empty
// list writes no chunk at all, an absent chunk means no pending timer, corrupt
// payloads throw rather than crash, and an unknown chunk appended after PTMR is
// still skipped.
//
// Every fixture is built in code — a save is OpenSky's own format and a
// synthetic PEX object is not game data. See docs/formats/opensky-save.md.

import Foundation
@testable import opensky
import Testing

struct OpenSkySaveTimerTests {
    // MARK: - Fixtures

    private static let alarmKey = PapyrusInstanceKey(
        reference: .plugin(name: "skyrim.esm", objectID: 0x0001_0BAD),
        scriptName: "AlarmScript"
    )

    private static let doorKey = PapyrusInstanceKey(
        reference: .generated(42),
        scriptName: "DoorScript"
    )

    /// One state per key kind, covering a repeating and a single-shot slot in
    /// each family plus a zero-delay slot that is already due.
    private static let states = [
        PapyrusTimerState(
            key: alarmKey, slot: .realRepeating, interval: 2.5, remaining: 1.25
        ),
        PapyrusTimerState(
            key: alarmKey, slot: .gameTimeSingleShot, interval: 3, remaining: 3
        ),
        PapyrusTimerState(
            key: doorKey, slot: .realSingleShot, interval: 0, remaining: 0
        ),
        PapyrusTimerState(
            key: doorKey, slot: .gameTimeRepeating, interval: 24, remaining: 0.5
        )
    ]

    private func encode(
        timers: [PapyrusTimerState],
        scripts: [PapyrusInstanceState] = []
    ) -> Data {
        OpenSkySaveEncoder.encode(
            snapshot: .empty,
            fingerprint: OpenSkySaveFixture.fingerprint,
            metadata: OpenSkySaveFixture.metadata,
            scripts: scripts,
            timers: timers
        )
    }

    /// A well-formed file with one hand-built `PTMR` chunk appended, for the
    /// malformed-payload cases. The decoder's chunk loop runs to end of file,
    /// so an appended chunk is read like any other.
    private func fileWithTimerPayload(_ payload: Data) -> Data {
        encode(timers: []) + OpenSkySaveFixture.chunk(
            OpenSkySaveFormat.ChunkTag.papyrusTimers, payload
        )
    }

    // MARK: - Round trip

    @Test func timerStateSurvivesARoundTrip() throws {
        let decoded = try OpenSkySaveDecoder.decode(encode(timers: Self.states))
        #expect(decoded.timers == Self.states)
        let first = try #require(decoded.timers.first)
        #expect(first.key == Self.alarmKey, "reference and script name are preserved")
        #expect(first.slot == .realRepeating)
        #expect(first.interval == 2.5)
        #expect(first.remaining == 1.25, "the delay is stored as time remaining")
        #expect(decoded.timers.map(\.slot) == [
            .realRepeating, .gameTimeSingleShot, .realSingleShot, .gameTimeRepeating
        ])
    }

    @Test func encodingIsDeterministic() {
        #expect(encode(timers: Self.states) == encode(timers: Self.states))
        #expect(encode(timers: Self.states) != encode(timers: []))
    }

    @Test func absentChunkMeansNoPendingTimers() throws {
        let decoded = try OpenSkySaveDecoder.decode(encode(timers: []))
        #expect(decoded.timers.isEmpty, "an empty list writes no PTMR chunk at all")
    }

    /// The additive-chunk contract: a session that armed no timer writes the
    /// exact bytes it wrote before this chunk existed.
    @Test func emptyTimerListWritesTheSameBytesAsOmittingTheParameter() {
        let without = OpenSkySaveEncoder.encode(
            snapshot: .empty,
            fingerprint: OpenSkySaveFixture.fingerprint,
            metadata: OpenSkySaveFixture.metadata
        )
        #expect(encode(timers: []) == without)
        #expect(
            OpenSkySaveFixture.offset(
                ofChunk: OpenSkySaveFormat.ChunkTag.papyrusTimers, in: without
            ) == nil
        )
    }

    // MARK: - Defensive decoding

    @Test func truncatedEntryIsRejected() {
        // Exactly one entry's worth of bytes, so the count check passes, but a
        // script-name length that runs past them, so the read fails inside the
        // entry rather than at the count.
        var payload = Data()
        payload.appendUInt32(1)
        payload.append(OpenSkySaveFixture.pluginKeyBytes())
        payload.appendUInt16(.max)
        payload.append(Data(count: OpenSkySaveFormat.minimumTimerEntrySize - 19))
        #expect(throws: OpenSkySaveError.truncated(context: "PTMR script name")) {
            try OpenSkySaveDecoder.decode(fileWithTimerPayload(payload))
        }
    }

    @Test func truncatedDurationIsRejected() {
        var payload = Self.entryPrefix(slot: 0)
        payload.appendUInt64(1.0.bitPattern)
        #expect(throws: OpenSkySaveError.truncated(context: "PTMR remaining")) {
            try OpenSkySaveDecoder.decode(fileWithTimerPayload(payload))
        }
    }

    @Test func bogusTimerCountIsRejected() {
        var payload = Data()
        payload.appendUInt32(.max)
        #expect(throws: OpenSkySaveError.self) {
            try OpenSkySaveDecoder.decode(fileWithTimerPayload(payload))
        }
    }

    /// Four slots are defined, so byte 4 is a shape this build cannot
    /// interpret at all — an error rather than a normalized value.
    @Test func unknownSlotIsRejected() {
        let payload = Self.entryPrefix(slot: 4)
        #expect(throws: OpenSkySaveError.invalidValue(context: "PTMR slot 4")) {
            try OpenSkySaveDecoder.decode(fileWithTimerPayload(payload))
        }
    }

    /// Stated policy, matching the `PSCR` float rule: a non-finite or negative
    /// duration is normalized to zero rather than rejected, which is also what
    /// the registry clamps such an interval to.
    @Test func nonFiniteAndNegativeDurationsNormalizeToZero() throws {
        for bad in [Double.nan, .infinity, -.infinity, -5] {
            let state = PapyrusTimerState(
                key: Self.doorKey, slot: .realRepeating, interval: bad, remaining: bad
            )
            let decoded = try OpenSkySaveDecoder.decode(encode(timers: [state]))
            let timer = try #require(decoded.timers.first)
            #expect(timer.interval == 0)
            #expect(timer.remaining == 0)
        }
    }

    @Test func unknownChunkAfterTimersIsSkipped() throws {
        var data = encode(timers: Self.states)
        data.append(Data("ZZZZ".utf8))
        data.appendUInt32(4)
        data.append(Data([1, 2, 3, 4]))
        let decoded = try OpenSkySaveDecoder.decode(data)
        #expect(decoded.timers == Self.states, "the file still decodes past an unknown chunk")
    }

    // MARK: - Runtime round trip

    /// The whole path a save takes: a live armed timer from a
    /// `PapyrusWorldRuntime` through the encoder and decoder and back into a
    /// *different* session, where it fires after exactly the delay that was
    /// left when the save was written.
    @MainActor
    @Test func liveTimerSurvivesASaveAndRestore() throws {
        let step = 1.0 / 30.0
        let source = try PapyrusUpdateTimerFixture.session(isPersistent: true)
        let handle = try #require(
            source.world.instancesByKey[PapyrusUpdateTimerFixture.instanceKey]
        )
        source.world.registerUpdateTimer(
            handle: handle, slot: .realSingleShot, interval: 1
        )
        for _ in 0 ..< 10 {
            _ = source.world.stepFixed()
        }
        let states = source.world.timerStates()
        let expectedRemaining = max(0, 1.0 - 10.0 * step)
        #expect(states.map(\.remaining) == [expectedRemaining])

        let decoded = try OpenSkySaveDecoder.decode(
            encode(timers: states, scripts: source.world.instanceStates())
        )
        #expect(decoded.timers == states)

        // Instances first, then timers: a saved timer names the instance it
        // belongs to, and a restore that cannot find it counts a skip.
        let target = try PapyrusUpdateTimerFixture.session(isPersistent: true)
        target.world.restore(instanceStates: decoded.scripts)
        target.world.restore(timerStates: decoded.timers)
        #expect(target.world.updateTimers.pendingCount == 1)
        #expect(target.world.skips.counts[.unknownSaveTimerTarget] == nil)

        var stepsSinceRestore = 0
        while
            PapyrusUpdateTimerFixture.updateNotes(target).isEmpty,
            stepsSinceRestore < 64
        {
            stepsSinceRestore += 1
            _ = target.world.stepFixed()
        }
        #expect(stepsSinceRestore == PapyrusUpdateTimerFixture.dueStep(
            interval: expectedRemaining, stepSeconds: step
        ))
        #expect(PapyrusUpdateTimerFixture.updateNotes(target).count == 1)
    }

    // MARK: - Helpers

    /// A declared count of one plus one entry's key, script name and slot
    /// byte, written by hand so a corruption case can put an exact bad value
    /// after it.
    private static func entryPrefix(slot: UInt8) -> Data {
        var payload = Data()
        payload.appendUInt32(1)
        payload.append(OpenSkySaveFixture.pluginKeyBytes())
        appendString("timerscript", to: &payload)
        payload.append(slot)
        return payload
    }

    /// The format's UInt16-length-prefixed UTF-8 string.
    private static func appendString(_ text: String, to data: inout Data) {
        let raw = Data(text.utf8)
        data.appendUInt16(UInt16(raw.count))
        data.append(raw)
    }
}
