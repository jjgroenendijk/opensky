// Synthetic Skyrim `.lip` builder. Cells are values on the documented frame grid,
// packed with the zero-run code; no game-derived bytes are fixtures.

import Foundation
@testable import OpenSkyFormatsAnimation

public enum LIPFixture: Sendable {
    public struct Cell: Sendable {
        public let frame: Int
        public let slot: Int
        public let value: Float

        public init(frame: Int, slot: Int, value: Float) {
            self.frame = frame
            self.slot = slot
            self.value = value
        }
    }

    public static let defaultCells = [
        Cell(frame: 0, slot: 0, value: 0.2),
        Cell(frame: 0, slot: 1, value: 0.4),
        Cell(frame: 1, slot: 0, value: 0.8),
        Cell(frame: 1, slot: 1, value: 0.6)
    ]

    /// The expanded body: frame count, first frame, target count, then the grid.
    public static func body(
        frameCount: UInt32 = 2,
        firstFrame: Int32 = 0,
        targetCount: UInt32 = 16,
        slotsPerFrame: Int = LIPFile.humanoidSlotsPerFrame,
        cells: [Cell] = defaultCells
    ) -> Data {
        var grid = [Float](repeating: 0, count: Int(frameCount) * slotsPerFrame)
        for cell in cells {
            grid[cell.frame * slotsPerFrame + cell.slot] = cell.value
        }
        var data = Data()
        data.appendUInt32(frameCount)
        data.appendUInt32(UInt32(bitPattern: firstFrame))
        data.appendUInt32(targetCount)
        for value in grid {
            data.appendFloat32(value)
        }
        return data
    }

    /// A whole file around `body`. `expandedSize` overrides the declared size.
    public static func file(
        version: UInt32 = 1,
        activeCurveCount: UInt32 = 2,
        expandedSize: UInt32? = nil,
        body: Data = body()
    ) -> Data {
        var data = Data()
        data.appendUInt32(version)
        data.appendUInt32(expandedSize ?? UInt32(body.count + 16))
        data.appendUInt32(activeCurveCount)
        data.append(LIPZeroRun.pack(body))
        return data
    }
}
