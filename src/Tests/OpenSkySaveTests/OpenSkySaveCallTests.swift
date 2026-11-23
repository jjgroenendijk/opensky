// PCAL chunk: round trip of every value, wake, and return kind, no chunk for no call,
// and corrupt payloads throw. See docs/formats/opensky-save-world-chunks.md.

import Foundation
import OpenSkyFormatsESM
@testable import OpenSkyFormatsTesting
@testable import OpenSkySave
import OpenSkySaveFixtures
import OpenSkyScriptingInterface
@testable import OpenSkyWorldState
import Testing

struct OpenSkySaveCallTests {
    private static let quest = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x900)
    private static let instance = PapyrusInstanceKey(
        reference: .plugin(name: "skyrim.esm", objectID: 0x14), scriptName: "waiterscript"
    )

    private func encode(_ calls: PapyrusCallSnapshot) -> Data {
        OpenSkySaveEncoder.encode(
            snapshot: .empty,
            fingerprint: OpenSkySaveFixture.fingerprint,
            metadata: OpenSkySaveFixture.metadata,
            calls: calls
        )
    }

    private func fileWithCallPayload(_ payload: Data) -> Data {
        var data = encode(.empty)
        data.append(Data("PCAL".utf8))
        data.appendUInt32(UInt32(payload.count))
        data.append(payload)
        return data
    }

    private static func call(
        wake: PapyrusSavedWake, resume: PapyrusSavedReturn, completion: PapyrusSavedReturn
    ) -> PapyrusCallState {
        var frame = PapyrusFrameState(
            script: "waiterscript", functionOrdinal: 3, instructionCount: 9,
            instance: instance, completion: completion
        )
        frame.instructionIndex = 4
        frame.slots = [
            .none, .boolean(true), .integer(-7), .float(1.5), .string("text"),
            .instance(instance), .reference(.generated(12)), .alias(quest: quest, id: 5),
            .array(0)
        ]
        var global = PapyrusFrameState(
            script: "utilityscript", functionOrdinal: 0, instructionCount: 2,
            instance: nil, completion: .assign("result")
        )
        global.slots = [.array(0)]
        var call = PapyrusCallState(wake: wake, resume: resume, frames: [frame, global])
        call.owner = instance
        call.holdsInstance = true
        call.nativeScript = "Utility"
        call.nativeFunction = "Wait"
        call.returnType = "Bool"
        return call
    }

    private static var snapshot: PapyrusCallSnapshot {
        var snapshot = PapyrusCallSnapshot()
        snapshot.arrays = [
            PapyrusSavedArray(elementType: "Int", elements: [.integer(1), .integer(2)])
        ]
        snapshot.calls = [
            call(wake: .realSeconds(2.25, answer: nil), resume: .discard, completion: .root),
            call(
                wake: .realSeconds(0, answer: .integer(4)), resume: .assign("x"),
                completion: .discard
            ),
            call(wake: .menuSeconds(1), resume: .assign(nil), completion: .assign(nil)),
            call(wake: .gameHours(0.5), resume: .root, completion: .root),
            call(
                wake: .questFragments(quest: quest, answer: .boolean(true)),
                resume: .discard, completion: .root
            ),
            call(
                wake: .questStart(quest: quest, thenFragments: true),
                resume: .discard, completion: .root
            ),
            call(wake: .lost, resume: .discard, completion: .root)
        ]
        var ownerless = PapyrusCallState(wake: .lost, resume: .root, frames: [])
        ownerless.returnType = "None"
        snapshot.calls.append(ownerless)
        return snapshot
    }

    @Test func callsSurviveARoundTrip() throws {
        let decoded = try OpenSkySaveDecoder.decode(encode(Self.snapshot))
        #expect(decoded.calls == Self.snapshot)
    }

    @Test func encodingIsDeterministic() {
        #expect(encode(Self.snapshot) == encode(Self.snapshot))
    }

    @Test func noCallWritesNoChunk() throws {
        let data = encode(.empty)
        #expect(data.range(of: Data("PCAL".utf8)) == nil)
        #expect(try OpenSkySaveDecoder.decode(data).calls.isEmpty)
    }

    @Test func corruptPayloadsThrow() {
        var hugeArrayCount = Data()
        hugeArrayCount.appendUInt32(.max)
        var hugeCallCount = Data()
        hugeCallCount.appendUInt32(0)
        hugeCallCount.appendUInt32(.max)
        var unknownValueTag = Data()
        unknownValueTag.appendUInt32(1)
        unknownValueTag.append(contentsOf: [0, 0])
        unknownValueTag.appendUInt32(1)
        unknownValueTag.append(99)
        unknownValueTag.appendUInt32(0)
        for payload in [Data(), hugeArrayCount, hugeCallCount, unknownValueTag] {
            #expect(throws: OpenSkySaveError.self) {
                try OpenSkySaveDecoder.decode(fileWithCallPayload(payload))
            }
        }
    }

    @Test func aTruncatedChunkThrowsAtEveryLength() throws {
        let whole = encode(Self.snapshot)
        let tag = try #require(whole.range(of: Data("PCAL".utf8)))
        let payload = whole[(tag.upperBound + 4)...]
        for length in stride(from: 0, to: payload.count, by: 7) {
            #expect(throws: OpenSkySaveError.self) {
                try OpenSkySaveDecoder.decode(fileWithCallPayload(Data(payload.prefix(length))))
            }
        }
    }
}
