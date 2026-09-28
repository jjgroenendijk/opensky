// Skyrim lodsettings/<worldspace>.lod, 16-byte little-endian layout.
// Reference: xEdit dev-4.1.6 Core/wbLOD.pas, TwbLodSettings.LoadFromData.

import Foundation
import OpenSkyFormatsCore

nonisolated public enum LODSettingsError: Error, Equatable, Sendable {
    case invalidSize(Int)
    case invalidStride(Int32)
    case invalidLevelRange(min: Int32, max: Int32)
}

nonisolated public struct LODSettings: Equatable, Sendable {
    public let origin: CellCoordinate
    public let stride: Int32
    public let minimumLevel: Int32
    public let maximumLevel: Int32

    public init(data: Data) throws {
        guard data.count == 16 else { throw LODSettingsError.invalidSize(data.count) }
        var reader = BinaryReader(data)
        origin = try CellCoordinate(
            x: Int32(Int16(bitPattern: reader.readUInt16())),
            y: Int32(Int16(bitPattern: reader.readUInt16()))
        )
        stride = try Int32(bitPattern: reader.readUInt32())
        minimumLevel = try Int32(bitPattern: reader.readUInt32())
        maximumLevel = try Int32(bitPattern: reader.readUInt32())
        guard stride > 0 else { throw LODSettingsError.invalidStride(stride) }
        guard minimumLevel > 0, minimumLevel <= maximumLevel else {
            throw LODSettingsError.invalidLevelRange(min: minimumLevel, max: maximumLevel)
        }
    }

    public var levels: [Int32] {
        var out: [Int32] = []
        var level = minimumLevel
        while level <= maximumLevel {
            out.append(level)
            guard level <= maximumLevel / 2 else { break }
            level *= 2
        }
        return out
    }

    public func blockOrigin(containing cell: CellCoordinate, level: Int32) -> CellCoordinate {
        CellCoordinate(
            x: origin.x + Self.floorDiv(cell.x - origin.x, by: level) * level,
            y: origin.y + Self.floorDiv(cell.y - origin.y, by: level) * level
        )
    }

    private static func floorDiv(_ value: Int32, by divisor: Int32) -> Int32 {
        let quotient = value / divisor
        let remainder = value % divisor
        return remainder < 0 ? quotient - 1 : quotient
    }
}
