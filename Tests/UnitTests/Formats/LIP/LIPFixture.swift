// Synthetic Skyrim `.lip` payload builder. Cells are authored as positions on
// the documented frame grid; no game-derived bytes are fixtures.

import Foundation
@testable import opensky

enum LIPFixture {
    struct Cell {
        let frame: Int
        let slot: Int
        let value: Float
        var duplicate = false

        func position(slotsPerFrame: Int = LIPFile.slotCount) -> Int {
            frame * slotsPerFrame + slot
        }
    }

    /// `headerPadding` reproduces the alternate header family, which carries
    /// extra bytes between the frame count and the tuple width (issue #449).
    /// `slotsPerFrame` drives both the grid and the duration field, because the
    /// two are the same fact on disk.
    static func file(
        version: UInt32 = 1,
        frameCount: UInt16 = 2,
        firstFrame: Int32 = 0,
        activeCurveCount: UInt32 = 2,
        tupleWidth: UInt16 = 3,
        targetCount: UInt16 = 16,
        unknownValue: UInt16 = 111,
        slotsPerFrame: Int = LIPFile.slotCount,
        headerPadding: [UInt8] = [],
        durationTicks: UInt32? = nil,
        // Replaces the generated token stream, for a payload whose framing is
        // the point of the test.
        payload: [UInt8]? = nil,
        cells: [Cell] = [
            Cell(frame: 0, slot: 0, value: 0.2),
            Cell(frame: 0, slot: 2, value: 0.4),
            Cell(frame: 1, slot: 0, value: 0.8),
            Cell(frame: 1, slot: 2, value: 0.6)
        ]
    ) -> Data {
        var data = Data()
        data.appendUInt32(version)
        data.appendUInt32(
            durationTicks ?? UInt32(Int(frameCount) * slotsPerFrame * 4 + 28)
        )
        data.appendUInt32(activeCurveCount)
        data.appendUInt16(frameCount)
        data.append(contentsOf: headerPadding)
        data.appendUInt16(tupleWidth)
        data.appendUInt32(UInt32(bitPattern: firstFrame))
        data.appendUInt16(targetCount)
        data.appendUInt16(unknownValue)
        if let payload {
            data.append(contentsOf: payload)
        } else {
            append(cells: cells, slotsPerFrame: slotsPerFrame, to: &data)
        }
        return data
    }

    private static func append(cells: [Cell], slotsPerFrame: Int, to data: inout Data) {
        let sorted = cells.sorted {
            $0.position(slotsPerFrame: slotsPerFrame)
                < $1.position(slotsPerFrame: slotsPerFrame)
        }
        for (index, cell) in sorted.enumerated() {
            data.appendFloat32(cell.value)
            if cell.duplicate {
                data.appendFloat32(cell.value)
            }
            guard sorted.indices.contains(index + 1) else { continue }
            let occupied = cell.duplicate ? 2 : 1
            let gap = sorted[index + 1].position(slotsPerFrame: slotsPerFrame)
                - cell.position(slotsPerFrame: slotsPerFrame) - occupied
            precondition((0 ... 63).contains(gap), "fixture gap exceeds one marker")
            if gap > 0 {
                data.append(contentsOf: [0, UInt8(gap * 4), 0])
            }
        }
    }
}
