// `BSFurnitureMarkerNode`: the places where an actor sits, lies, or leans on a
// furniture mesh. Layout: docs/formats/nif.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct NIFFurnitureMarker: Equatable, Sendable {
    public static let typeNames: Set = ["BSFurnitureMarkerNode", "BSFurnitureMarker"]

    /// Model space, in game units.
    public let offset: SIMD3<Float>
    /// Radians, added to the reference's own z rotation.
    public let heading: Float
    /// 1 sit, 2 sleep, 4 lean.
    public let animationType: UInt16
    /// 0x01 front, 0x02 behind, 0x04 right, 0x08 left, 0x10 up.
    public let entryPoints: UInt16

    public init(offset: SIMD3<Float>, heading: Float, animationType: UInt16, entryPoints: UInt16) {
        self.offset = offset
        self.heading = heading
        self.animationType = animationType
        self.entryPoints = entryPoints
    }

    /// A name index and a count, then 20 bytes per marker (Skyrim layout).
    public static func decode(_ data: Data) throws -> [NIFFurnitureMarker] {
        var reader = BinaryReader(data)
        _ = try reader.readUInt32()
        let count = try reader.readUInt32()
        guard Int(count) * 20 <= reader.bytesRemaining else {
            throw NIFError.malformed("BSFurnitureMarker lists \(count) markers past its end")
        }
        return try (0 ..< count).map { _ in
            try NIFFurnitureMarker(
                offset: SIMD3(reader.readFloat32(), reader.readFloat32(), reader.readFloat32()),
                heading: reader.readFloat32(),
                animationType: reader.readUInt16(),
                entryPoints: reader.readUInt16()
            )
        }
    }

    /// The markers of the first marker block in the file. A malformed block gives none.
    public static func markers(in file: NIFFile) -> [NIFFurnitureMarker] {
        file.blocks.lazy.filter { typeNames.contains($0.typeName) }
            .compactMap { try? decode($0.data) }
            .first ?? []
    }
}
