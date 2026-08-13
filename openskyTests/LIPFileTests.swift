// Defensive `.lip` header, sparse-grid and sampling tests. Every byte is built
// by LIPFixture; no installed voice data enters the unit target.

import Foundation
@testable import opensky
import Testing

@Suite("LIP facial-animation track")
struct LIPFileTests {
    @Test("header and positional keys decode")
    func headerAndKeys() throws {
        let file = try LIPFile(data: LIPFixture.file())

        #expect(file.header.durationTicks == 292)
        #expect(file.header.activeCurveCount == 2)
        #expect(file.header.frameCount == 2)
        #expect(file.header.firstFrame == 0)
        #expect(file.header.unknownValue == 111)
        #expect(file.keys.map(\.slot) == [0, 2, 0, 2])
        #expect(file.keys.map(\.frame) == [0, 0, 1, 1])
        #expect(file.markerCount == 3)
    }

    @Test("sampling interpolates and clamps at the track end")
    func sampling() throws {
        let file = try LIPFile(data: LIPFixture.file())
        let midpoint = file.sample(at: 0.5 / LIPFile.framesPerSecond)
        let end = file.sample(at: 50)

        #expect(abs((midpoint.weightsBySlot[0] ?? 0) - 0.5) < 0.0001)
        #expect(abs((midpoint.weightsBySlot[2] ?? 0) - 0.5) < 0.0001)
        #expect(abs((end.weightsBySlot[0] ?? 0) - 0.8) < 0.0001)
        #expect(abs((end.weightsBySlot[2] ?? 0) - 0.6) < 0.0001)
    }

    @Test("negative first frame anchors audio time at the pre-roll offset")
    func preRoll() throws {
        let file = try LIPFile(data: LIPFixture.file(
            frameCount: 3,
            firstFrame: -1,
            cells: [
                .init(frame: 0, slot: 0, value: 0.1),
                .init(frame: 1, slot: 0, value: 0.5),
                .init(frame: 2, slot: 0, value: 0.9)
            ]
        ))

        #expect(abs((file.sample(at: 0).weightsBySlot[0] ?? 0) - 0.5) < 0.0001)
        #expect(abs(file.duration - (2.0 / 30.0)) < 0.0001)
    }

    @Test("duplicate float tokens are retained as an uncertain field tally")
    func duplicateToken() throws {
        let file = try LIPFile(data: LIPFixture.file(cells: [
            .init(frame: 0, slot: 0, value: 0.25, duplicate: true),
            .init(frame: 0, slot: 2, value: 0.75)
        ]))

        #expect(file.duplicateValueCount == 1)
        #expect(file.keys.first?.hasDuplicate == true)
        #expect(file.keys.map(\.slot) == [0, 2])
    }

    @Test("the alternate header family's extra bytes are located, not guessed")
    func alternateHeaderLayout() throws {
        // One extra byte between the frame count and the tuple width, tuple
        // width 2, everything else standard: the shape 4,975 vanilla blobs
        // carry (issue #449).
        let file = try LIPFile(data: LIPFixture.file(
            tupleWidth: 2, headerPadding: [0]
        ))

        #expect(file.header.headerSize == 25)
        #expect(file.header.tupleWidth == 2)
        #expect(file.header.targetCount == 16)
        #expect(file.header.slotsPerFrame == 33)
        #expect(file.keys.map(\.slot) == [0, 2, 0, 2])
    }

    @Test("a curve count past the vocabulary is recorded, not rejected")
    func curveCountPastVocabulary() throws {
        // 952 vanilla creature blobs declare nine curves against a vocabulary
        // of eight. Nothing indexes by the field (issue #449).
        let file = try LIPFile(data: LIPFixture.file(activeCurveCount: 17))

        #expect(file.header.activeCurveCount == 17)
        #expect(file.header.targetCount == 16)
    }

    @Test("the slot stride comes from the tick budget, not a constant")
    func creatureStride() throws {
        // The 8-target creature family: 32 ticks per frame, eight slots.
        let file = try LIPFile(data: LIPFixture.file(
            frameCount: 2,
            activeCurveCount: 2,
            targetCount: 8,
            slotsPerFrame: 8,
            cells: [
                .init(frame: 0, slot: 0, value: 0.2),
                .init(frame: 1, slot: 3, value: 0.6)
            ]
        ))

        #expect(file.header.durationTicks == 92)
        #expect(file.header.slotsPerFrame == 8)
        #expect(file.header.targetCount == 8)
        #expect(file.keys.map(\.frame) == [0, 1])
        #expect(file.keys.map(\.slot) == [0, 3])
    }

    @Test("an ambiguous marker triple is resolved against the whole payload")
    func ambiguousMarkerFraming() throws {
        // The second value's own first three bytes read as a `00 04 00` suffix.
        // Taking them as a suffix leaves a byte over at the end, so the only
        // framing that spans the payload is the one that reads them as data.
        let file = try LIPFile(data: LIPFixture.file(payload: [
            0x00, 0x00, 0x80, 0x3E, // 0.25
            0x00, 0x04, 0x00, 0x3E, // 0.12501526, and a suffix-shaped prefix
            0x00, 0x00, 0x00, 0x3F // 0.5
        ]))

        #expect(file.keys.map(\.slot) == [0, 1, 2])
        #expect(file.keys.map(\.value) == [0.25, 0.125_015_26, 0.5])
        #expect(file.markerCount == 0)
    }

    @Test("unsupported header variants are declined", arguments: [
        LIPFixture.file(version: 2),
        LIPFixture.file(tupleWidth: 4),
        LIPFixture.file(targetCount: 43)
    ])
    func unsupportedHeader(data: Data) {
        #expect(throws: LIPError.self) { try LIPFile(data: data) }
    }

    @Test("malformed inputs throw rather than indexing past data")
    func malformedInputs() {
        #expect(throws: LIPError.self) { try LIPFile(data: Data()) }
        #expect(throws: LIPError.self) {
            try LIPFile(data: LIPFixture.file(frameCount: 0, cells: []))
        }
        #expect(throws: LIPError.self) {
            try LIPFile(data: LIPFixture.file(durationTicks: 1))
        }
        #expect(throws: LIPError.self) {
            try LIPFile(data: LIPFixture.file(cells: [.init(
                frame: 0, slot: 0, value: .nan
            )]))
        }
    }

    @Test("a truncated payload never escapes the declared grid", arguments: 1 ... 6)
    func truncatedPayload(cut: Int) {
        // Marker framing is ambiguous (issue #449), so a payload missing a few
        // bytes sometimes frames as a shorter track rather than as a failure —
        // the decoder cannot tell the two apart from the bytes alone. What it
        // must never do is read past the blob or place a key outside the grid
        // the header declares.
        var data = LIPFixture.file()
        data.removeLast(cut)
        guard let file = try? LIPFile(data: data) else { return }

        #expect(file.keys.allSatisfy { $0.slot < file.header.slotsPerFrame })
        #expect(file.keys.allSatisfy { $0.frame < file.header.frameCount })
    }

    @Test("a header cut short is rejected")
    func truncatedHeader() {
        var data = LIPFixture.file()
        data.removeLast(data.count - 20)
        #expect(throws: LIPError.self) { try LIPFile(data: data) }
    }
}
