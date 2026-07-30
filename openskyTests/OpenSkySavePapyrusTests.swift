// PSCR chunk coverage for the OpenSky native save container (issue #171):
// Papyrus script instance state round-trips, bytes stay deterministic, an
// absent chunk means no saved script state, corrupt payloads throw rather than
// crash, and an unknown chunk appended after PSCR is still skipped.
//
// Every fixture is built in code — a save is OpenSky's own format and a
// synthetic PEX object is not game data. See docs/formats/opensky-save.md.

import Foundation
@testable import opensky
import Testing

struct OpenSkySavePapyrusTests {
    // MARK: - Fixtures

    private static let alarmKey = PapyrusInstanceKey(
        reference: .plugin(name: "skyrim.esm", objectID: 0x0001_0BAD),
        scriptName: "AlarmScript"
    )

    private static let doorKey = PapyrusInstanceKey(
        reference: .generated(42),
        scriptName: "DoorScript"
    )

    /// One instance per key kind, covering every value tag, an empty active
    /// state, a non-ASCII string, and both settings of the `OnInit` flag.
    private static let states = [
        PapyrusInstanceState(
            key: alarmKey,
            activeState: "Triggered",
            variables: [
                PapyrusVariableState(
                    declaringScript: "AlarmScript", name: "armed", value: .boolean(true)
                ),
                PapyrusVariableState(
                    declaringScript: "AlarmScript", name: "count", value: .integer(-9)
                ),
                PapyrusVariableState(
                    declaringScript: "AlarmScript", name: "delay", value: .float(2.5)
                ),
                PapyrusVariableState(
                    declaringScript: "AlarmScript", name: "label", value: .string("vílja")
                ),
                PapyrusVariableState(
                    declaringScript: "AlarmScript", name: "spare", value: .none
                )
            ],
            hasFiredOnInit: true
        ),
        PapyrusInstanceState(
            key: doorKey,
            activeState: "",
            variables: [],
            hasFiredOnInit: false
        )
    ]

    private func encode(scripts: [PapyrusInstanceState]) -> Data {
        OpenSkySaveEncoder.encode(
            snapshot: .empty,
            fingerprint: OpenSkySaveFixture.fingerprint,
            metadata: OpenSkySaveFixture.metadata,
            scripts: scripts
        )
    }

    /// A well-formed file with one hand-built `PSCR` chunk appended, for the
    /// malformed-payload cases. The decoder's chunk loop runs to end of file,
    /// so an appended chunk is read like any other.
    private func fileWithScriptPayload(_ payload: Data) -> Data {
        var data = encode(scripts: [])
        data.append(Data("PSCR".utf8))
        data.appendUInt32(UInt32(payload.count))
        data.append(payload)
        return data
    }

    // MARK: - Round trip

    @Test func scriptStateSurvivesARoundTrip() throws {
        let decoded = try OpenSkySaveDecoder.decode(encode(scripts: Self.states))
        #expect(decoded.scripts == Self.states)
        let alarm = try #require(decoded.scripts.first)
        #expect(alarm.key == Self.alarmKey, "reference and script name are preserved")
        #expect(alarm.activeState == "Triggered")
        #expect(alarm.hasFiredOnInit)
        #expect(decoded.scripts.last?.hasFiredOnInit == false)
    }

    @Test func encodingIsDeterministic() {
        #expect(encode(scripts: Self.states) == encode(scripts: Self.states))
        #expect(encode(scripts: Self.states) != encode(scripts: []))
    }

    @Test func absentChunkMeansNoScriptState() throws {
        let decoded = try OpenSkySaveDecoder.decode(encode(scripts: []))
        #expect(decoded.scripts.isEmpty, "an empty list writes no PSCR chunk at all")
    }

    // MARK: - Defensive decoding

    @Test func truncatedEntryIsRejected() {
        // One declared instance and just enough bytes for its key, so the
        // count check passes and the read runs out inside the entry.
        var payload = Data()
        payload.appendUInt32(1)
        payload.append(OpenSkySaveFixture.pluginKeyBytes())
        #expect(throws: OpenSkySaveError.truncated(context: "PSCR script name")) {
            try OpenSkySaveDecoder.decode(fileWithScriptPayload(payload))
        }
    }

    @Test func bogusInstanceCountIsRejected() {
        var payload = Data()
        payload.appendUInt32(.max)
        #expect(throws: OpenSkySaveError.self) {
            try OpenSkySaveDecoder.decode(fileWithScriptPayload(payload))
        }
    }

    @Test func bogusVariableCountIsRejected() {
        var payload = Data()
        payload.appendUInt32(1)
        payload.append(OpenSkySaveFixture.pluginKeyBytes())
        OpenSkySavePapyrusTests.appendString("alarmscript", to: &payload)
        OpenSkySavePapyrusTests.appendString("", to: &payload)
        payload.append(0)
        payload.appendUInt32(.max)
        #expect(throws: OpenSkySaveError.self) {
            try OpenSkySaveDecoder.decode(fileWithScriptPayload(payload))
        }
    }

    @Test func unknownValueTagIsRejected() {
        var payload = Data()
        payload.appendUInt32(1)
        payload.append(OpenSkySaveFixture.pluginKeyBytes())
        OpenSkySavePapyrusTests.appendString("alarmscript", to: &payload)
        OpenSkySavePapyrusTests.appendString("", to: &payload)
        payload.append(0)
        payload.appendUInt32(1)
        OpenSkySavePapyrusTests.appendString("alarmscript", to: &payload)
        OpenSkySavePapyrusTests.appendString("armed", to: &payload)
        payload.append(0x7F)
        #expect(throws: OpenSkySaveError.invalidValue(context: "PSCR value tag 127")) {
            try OpenSkySaveDecoder.decode(fileWithScriptPayload(payload))
        }
    }

    /// Stated policy: a non-finite float is normalized to zero rather than
    /// rejected, because Papyrus arithmetic can legitimately produce one and
    /// refusing a whole world over it would be the worse failure.
    @Test func nonFiniteFloatsNormalizeToZero() throws {
        for bad in [Float.nan, .infinity, -.infinity] {
            let state = PapyrusInstanceState(
                key: Self.doorKey,
                activeState: "",
                variables: [PapyrusVariableState(
                    declaringScript: "DoorScript", name: "drift", value: .float(bad)
                )],
                hasFiredOnInit: false
            )
            let decoded = try OpenSkySaveDecoder.decode(encode(scripts: [state]))
            let variable = try #require(decoded.scripts.first?.variables.first)
            #expect(variable.value == .float(0))
        }
    }

    @Test func unknownChunkAfterScriptsIsSkipped() throws {
        var data = encode(scripts: Self.states)
        data.append(Data("ZZZZ".utf8))
        data.appendUInt32(4)
        data.append(Data([1, 2, 3, 4]))
        let decoded = try OpenSkySaveDecoder.decode(data)
        #expect(decoded.scripts == Self.states, "the file still decodes past an unknown chunk")
    }

    // MARK: - Runtime round trip

    /// The whole path a save takes: live instances from a `PapyrusWorldRuntime`
    /// through the encoder and decoder and back into a *different* runtime.
    @MainActor
    @Test func liveRuntimeStateSurvivesASaveAndRestore() throws {
        let object = Self.alarmObject()
        let world = PapyrusWorldFixture.worldRuntime(
            objects: [object], nativeDispatch: PapyrusWorldProbeDispatch()
        )
        let entry = try PapyrusWorldFixture.referenceEntry(
            objectID: 0x30, scripts: [VMADFixture.Script("Alarm", properties: [])]
        )
        world.attach(
            cell: PapyrusWorldFixture.cell,
            references: PapyrusWorldFixture.index([entry]),
            formIDResolver: PapyrusWorldFixture.resolver,
            firstIntegration: true
        )
        PapyrusWorldFixture.drain(world)

        let key = PapyrusWorldFixture.key(objectID: 0x30, script: "Alarm")
        let handle = try #require(world.instancesByKey[key])
        let instance = try #require(world.runtime.instance(for: handle))
        #expect(instance.setValue(.integer(7), named: "count", declaredBy: "Alarm"))
        #expect(instance.setValue(.string("armed"), named: "label", declaredBy: "Alarm"))
        instance.activeState = "Triggered"

        let decoded = try OpenSkySaveDecoder.decode(encode(scripts: world.instanceStates()))

        let fresh = PapyrusWorldFixture.worldRuntime(
            objects: [object], nativeDispatch: PapyrusWorldProbeDispatch()
        )
        fresh.restore(instanceStates: decoded.scripts)
        let restoredHandle = try #require(fresh.instancesByKey[key])
        let restored = try #require(fresh.runtime.instance(for: restoredHandle))
        #expect(restored.activeState == "Triggered")
        #expect(restored.value(named: "count", declaredBy: "Alarm") == .integer(7))
        #expect(restored.value(named: "label", declaredBy: "Alarm") == .string("armed"))
        #expect(fresh.firedOnInit.contains(key), "OnInit never re-fires after a load")
    }

    // MARK: - Helpers

    /// A script with one integer and one string variable, plus an `OnInit`
    /// handler so the fired flag is exercised end to end.
    private static func alarmObject() -> PexObject {
        PapyrusWorldFixture.eventScript(
            "Alarm",
            events: [("OnInit", PapyrusWorldFixture.probeBody(note: "alarm.oninit"))],
            variables: [
                PexVariable(
                    name: "count", typeName: "Int", userFlags: 0, initialValue: .integer(0)
                ),
                PexVariable(
                    name: "label", typeName: "String", userFlags: 0, initialValue: .string("")
                )
            ]
        )
    }

    /// The format's UInt16-length-prefixed UTF-8 string, written by hand so a
    /// corruption case can put an exact bad byte after it.
    private static func appendString(_ text: String, to data: inout Data) {
        let raw = Data(text.utf8)
        data.appendUInt16(UInt16(raw.count))
        data.append(raw)
    }
}
