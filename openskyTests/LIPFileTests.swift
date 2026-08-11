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
            try LIPFile(data: LIPFixture.file(activeCurveCount: 17))
        }
        #expect(throws: LIPError.self) {
            try LIPFile(data: LIPFixture.file(cells: [.init(
                frame: 0, slot: 0, value: .nan
            )]))
        }
    }

    @Test("truncated payload suffix is rejected")
    func truncatedPayload() {
        var data = LIPFixture.file()
        data.removeLast(2)
        #expect(throws: LIPError.self) { try LIPFile(data: data) }
    }
}
