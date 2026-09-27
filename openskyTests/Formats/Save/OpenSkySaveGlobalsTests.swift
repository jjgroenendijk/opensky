// GVAR chunk coverage for the OpenSky native save container (issue #165): the
// runtime global overrides round-trip, the bytes stay deterministic, an absent
// chunk means no overrides, and a corrupt payload throws rather than crashes.
// See docs/formats/opensky-save.md.

import Foundation
@testable import opensky
import Testing

@MainActor
struct OpenSkySaveGlobalsTests {
    private func encode(_ snapshot: WorldStateSnapshot) -> Data {
        OpenSkySaveEncoder.encode(
            snapshot: snapshot,
            fingerprint: OpenSkySaveFixture.fingerprint,
            metadata: OpenSkySaveFixture.metadata
        )
    }

    @Test func globalsSurviveARoundTrip() throws {
        let store = WorldStateStore()
        store.setGlobal(3.7, type: .short, for: GlobalFixture.key(0x0802))
        store.setGlobal(-1_234_567, type: .long, for: GlobalFixture.key(0x0801))
        store.setGlobal(0.125, type: .float, for: GlobalFixture.key(0x0800))
        let snapshot = store.snapshot()

        let decoded = try OpenSkySaveDecoder.decode(encode(snapshot))
        #expect(decoded.snapshot.globals == snapshot.globals)
        #expect(decoded.snapshot == snapshot)
        // Declared types come back, not just the numbers.
        #expect(decoded.snapshot.globalValue(for: GlobalFixture.key(0x0802))
            == GlobalValue(type: .short, rawValue: 4))
        #expect(decoded.snapshot.globalValue(for: GlobalFixture.key(0x0801))?.type == .long)
    }

    /// Two stores that reached the same globals through different write orders
    /// must produce identical bytes.
    @Test func encodingIsDeterministic() {
        let first = WorldStateStore()
        first.setGlobal(1, type: .short, for: GlobalFixture.key(0x0800))
        first.setGlobal(2, type: .float, for: GlobalFixture.key(0x0900))

        let second = WorldStateStore()
        second.setGlobal(9, type: .float, for: GlobalFixture.key(0x0900))
        second.setGlobal(1, type: .short, for: GlobalFixture.key(0x0800))
        second.setGlobal(2, type: .float, for: GlobalFixture.key(0x0900))

        #expect(encode(first.snapshot()) == encode(second.snapshot()))
    }

    @Test func restoringADecodedSaveRebuildsTheStore() throws {
        let source = WorldStateStore()
        source.setGlobal(42, type: .long, for: GlobalFixture.key(0x0800))
        let decoded = try OpenSkySaveDecoder.decode(encode(source.snapshot()))

        let target = WorldStateStore()
        target.setGlobal(7, type: .short, for: GlobalFixture.key(0x0999))
        target.restore(from: decoded.snapshot)
        #expect(target.overriddenGlobalCount == 1)
        #expect(target.globalValue(for: GlobalFixture.key(0x0800))?.value == 42)
        #expect(target.globalValue(for: GlobalFixture.key(0x0999)) == nil)
    }

    @Test func saveWithNoOverriddenGlobalsDecodesEmpty() throws {
        let decoded = try OpenSkySaveDecoder.decode(encode(.empty))
        #expect(decoded.snapshot.globals.isEmpty)
    }

    @Test func unknownValueTypeTagIsRejected() {
        var payload = Data()
        payload.appendUInt32(1)
        payload.append(Data([OpenSkySaveFormat.KeyTag.plugin]))
        payload.appendUInt16(0) // empty plugin name
        payload.appendUInt32(0x0800)
        payload.append(Data([9])) // no such declared type
        payload.appendUInt32(Float(1).bitPattern)
        #expect(throws: OpenSkySaveError.self) {
            try OpenSkySaveEntryDecoder.decodeGlobals(payload)
        }
    }

    @Test func impossibleEntryCountIsRejected() {
        var payload = Data()
        payload.appendUInt32(.max)
        #expect(throws: OpenSkySaveError.self) {
            try OpenSkySaveEntryDecoder.decodeGlobals(payload)
        }
    }

    @Test func truncatedEntryIsRejected() {
        var payload = Data()
        payload.appendUInt32(1)
        payload.append(Data([OpenSkySaveFormat.KeyTag.plugin]))
        payload.appendUInt16(0)
        payload.appendUInt32(0x0800)
        payload.append(Data([Global.ValueType.float.saveTag]))
        // Value bytes missing.
        #expect(throws: OpenSkySaveError.self) {
            try OpenSkySaveEntryDecoder.decodeGlobals(payload)
        }
    }
}
