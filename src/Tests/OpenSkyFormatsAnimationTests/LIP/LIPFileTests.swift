// `.lip` header, zero-run expansion, grid, and sampling tests. Every byte is built
// by LIPFixture; no installed voice data enters the unit target.

import Foundation
@testable import OpenSkyFormatsAnimation
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite("LIP facial-animation track", .tags(.parser))
struct LIPFileTests {
    @Test("header and grid decode")
    func headerAndGrid() throws {
        let body = LIPFixture.body(frameCount: 3, firstFrame: -1)
        let file = try LIPFile(data: LIPFixture.file(body: body))

        #expect(file.header.expandedSize == body.count + 16)
        #expect(file.header.frameCount == 3)
        #expect(file.header.firstFrame == -1)
        #expect(file.header.targetCount == 16)
        #expect(file.header.slotsPerFrame == 33)
        #expect(file.header.activeCurveCount == 2)
        #expect(file.values.count == 99)
        #expect(file.value(frame: 1, slot: 1) == 0.6)
        #expect(file.value(frame: 2, slot: 0) == 0)
        #expect(file.activeSlots == [0, 1])
        #expect(abs(file.duration - 2.0 / 30) < 0.0001)
    }

    @Test("the creature grid has one slot per target")
    func creatureGrid() throws {
        let file = try LIPFile(data: LIPFixture.file(body: LIPFixture.body(
            targetCount: 8, slotsPerFrame: 8,
            cells: [.init(frame: 1, slot: 7, value: 0.5)]
        )))

        #expect(file.header.slotsPerFrame == 8)
        #expect(file.value(frame: 1, slot: 7) == 0.5)
    }

    @Test("sampling interpolates between frames and holds at both ends")
    func sampling() throws {
        let file = try LIPFile(data: LIPFixture.file())

        let midpoint = file.sample(at: 0.5 / LIPFile.framesPerSecond)
        #expect(abs(midpoint.value(at: 0) - 0.5) < 0.0001)
        #expect(abs(midpoint.value(at: 1) - 0.5) < 0.0001)
        #expect(file.sample(at: -1).value(at: 0) == 0.2)
        #expect(abs(file.sample(at: 10).value(at: 1) - 0.6) < 0.0001)
        #expect(file.sample(at: .nan).value(at: 0) == 0.2)
        #expect(file.sample(at: 0).values.count == 33)
    }

    @Test("a negative first frame shifts the grid before the audio")
    func preRoll() throws {
        let file = try LIPFile(data: LIPFixture.file(
            body: LIPFixture.body(frameCount: 2, firstFrame: -1)
        ))

        #expect(abs(file.sample(at: 0).value(at: 0) - 0.8) < 0.0001)
        #expect(abs(file.duration - 1.0 / 30) < 0.0001)
    }

    @Test("a positive first frame starts the grid after the audio")
    func lateStart() throws {
        let file = try LIPFile(data: LIPFixture.file(
            body: LIPFixture.body(frameCount: 2, firstFrame: 3)
        ))

        #expect(file.sample(at: 0).value(at: 0) == 0.2)
        #expect(abs(file.sample(at: 4.0 / 30).value(at: 0) - 0.8) < 0.0001)
        #expect(abs(file.duration - 5.0 / 30) < 0.0001)
    }

    @Test("values keep their sign; clamping is the mapping's job")
    func signedValues() throws {
        let file = try LIPFile(data: LIPFixture.file(body: LIPFixture.body(
            cells: [.init(frame: 0, slot: 30, value: -0.07)]
        )))

        #expect(file.sample(at: 0).value(at: 30) == -0.07)
    }

    @Test("a zero run longer than one count field expands")
    func longZeroRun() throws {
        let packed = LIPZeroRun.pack([1] + [UInt8](repeating: 0, count: 70000) + [2])
        let expanded = try LIPZeroRun.expand(packed, to: 70002)

        #expect(packed.count == 8)
        #expect(expanded.first == 1)
        #expect(expanded.last == 2)
        #expect(expanded.dropFirst().dropLast().allSatisfy { $0 == 0 })
    }

    @Test("bad headers and bodies throw instead of trapping", arguments: [
        LIPFixture.file(version: 2),
        LIPFixture.file(expandedSize: 1),
        LIPFixture.file(expandedSize: 0xFFFF_FFFF),
        LIPFixture.file(expandedSize: UInt32(LIPFixture.body().count + 20)),
        LIPFixture.file(expandedSize: UInt32(LIPFixture.body().count + 12)),
        LIPFixture.file(body: LIPFixture.body(frameCount: 0, cells: [])),
        LIPFixture.file(body: LIPFixture.body(firstFrame: -3)),
        LIPFixture.file(body: LIPFixture.body(firstFrame: 20000)),
        LIPFixture.file(body: LIPFixture.body(targetCount: 0)),
        LIPFixture.file(body: LIPFixture.body(targetCount: 34)),
        LIPFixture.file(body: LIPFixture.body(cells: [.init(frame: 0, slot: 0, value: .nan)])),
        LIPFixture.file().dropLast(),
        Data(),
        Data([1, 0, 0, 0])
    ])
    func rejects(_ data: Data) {
        #expect(throws: LIPError.self) { try LIPFile(data: data) }
    }

    @Test("a grid that does not fill whole frames throws")
    func partialFrame() {
        var body = LIPFixture.body()
        body.append(contentsOf: [0x3F, 0x3F])
        #expect(throws: LIPError.self) {
            try LIPFile(data: LIPFixture.file(body: body))
        }
    }

    @Test("a zero run cut off at the end throws")
    func truncatedRun() {
        var data = LIPFixture.file(expandedSize: 40)
        data = data.prefix(12) + Data([1, 0, 4])
        #expect(throws: LIPError.self) { try LIPFile(data: data) }
    }
}
