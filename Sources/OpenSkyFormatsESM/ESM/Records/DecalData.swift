// DODT decal data, shared by IPCT and TXST. 36 bytes in xEdit dev-4.1.6
// `wbDODT`. Layout and sources: docs/formats/records.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct DecalData: Equatable, Sendable {
    public struct Flags: OptionSet, Equatable, Sendable {
        public let rawValue: UInt8

        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        public static let parallax = Flags(rawValue: 0x01)
        public static let alphaBlending = Flags(rawValue: 0x02)
        public static let alphaTesting = Flags(rawValue: 0x04)
        public static let noSubtextures = Flags(rawValue: 0x08)
    }

    public let minWidth: Float
    public let maxWidth: Float
    public let minHeight: Float
    public let maxHeight: Float
    public let depth: Float
    public let shininess: Float
    public let parallaxScale: Float
    public let parallaxPasses: UInt8
    public let flags: Flags
    /// RGB, 0-255 each.
    public let color: SIMD3<UInt8>

    public init(_ reader: inout BinaryReader) throws {
        minWidth = try reader.readFloat32()
        maxWidth = try reader.readFloat32()
        minHeight = try reader.readFloat32()
        maxHeight = try reader.readFloat32()
        depth = try reader.readFloat32()
        shininess = try reader.readFloat32()
        parallaxScale = try reader.readFloat32()
        parallaxPasses = try reader.readUInt8()
        flags = try Flags(rawValue: reader.readUInt8())
        reader.skip(2) // unknown
        color = try SIMD3(reader.readUInt8(), reader.readUInt8(), reader.readUInt8())
    }
}
