// WRLD fields beyond the core `Worldspace` decode: map data and offsets,
// bounds, LOD water, large references, and raw height and offset tables.
// Layout and sources: docs/formats/world-records.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct WorldspaceMapData: Equatable, Sendable {
    /// The map size in pixels.
    public let usableDimensions: SIMD2<Int32>
    public let northWestCell: SIMD2<Int16>
    public let southEastCell: SIMD2<Int16>
    public let cameraMinHeight: Float?
    public let cameraMaxHeight: Float?
    public let cameraInitialPitch: Float?

    init(_ reader: inout BinaryReader) throws {
        usableDimensions = try SIMD2(reader.readInt32(), reader.readInt32())
        northWestCell = try SIMD2(reader.readInt16(), reader.readInt16())
        southEastCell = try SIMD2(reader.readInt16(), reader.readInt16())
        let hasCamera = reader.bytesRemaining >= 12
        cameraMinHeight = try hasCamera ? reader.readFloat32() : nil
        cameraMaxHeight = try hasCamera ? reader.readFloat32() : nil
        cameraInitialPitch = try hasCamera ? reader.readFloat32() : nil
    }
}

/// ONAM: how the world map image lines up with the world.
nonisolated public struct WorldspaceMapOffset: Equatable, Sendable {
    public let scale: Float
    public let offset: SIMD3<Float>
}

/// One RNAM cell: the large references that load with it.
nonisolated public struct WorldspaceLargeReferenceCell: Equatable, Sendable {
    nonisolated public struct Reference: Equatable, Sendable {
        public let reference: FormID
        public let cell: SIMD2<Int16>
    }

    public let cell: SIMD2<Int16>
    public let references: [Reference]

    init(_ reader: inout BinaryReader) throws {
        let y = try reader.readInt16()
        let x = try reader.readInt16()
        cell = SIMD2(x, y)
        let count = try Int(reader.readUInt32())
        var references: [Reference] = []
        for _ in 0 ..< count {
            let reference = try reader.readFormID()
            let refY = try reader.readInt16()
            let refX = try reader.readInt16()
            references.append(Reference(reference: reference, cell: SIMD2(refX, refY)))
        }
        self.references = references
    }
}

nonisolated public struct WorldspaceDetails: Equatable, Sendable {
    public var largeReferences: [WorldspaceLargeReferenceCell] = []
    /// MHDT: min and max cell, then four uint8 heights per cell. Kept raw.
    public var maxHeightData: Data?
    /// WCTR.
    public var fixedCenter: SIMD2<Int16>?
    /// LTMP, an LGTM.
    public var interiorLighting: FormID?
    /// XLCN, an LCTN.
    public var location: FormID?
    /// NAM3, a WATR, and NAM4.
    public var lodWater: FormID?
    public var lodWaterHeight: Float?
    /// ICON.
    public var mapImage: String?
    public var cloudModel: ModelData?
    public var map: WorldspaceMapData?
    public var mapOffset: WorldspaceMapOffset?
    /// NAMA.
    public var distantLODMultiplier: Float?
    /// NAM0 and NAM9, in game units.
    public var boundsMin: SIMD2<Float>?
    public var boundsMax: SIMD2<Float>?
    /// NNAM, unused by the game.
    public var canopyShadow: String?
    public var waterNoiseTexture: String?
    public var waterEnvironmentMap: String?
    /// TNAM and UNAM.
    public var hdLODDiffuseTexture: String?
    public var hdLODNormalTexture: String?
    /// OFST, one uint32 per cell. Kept raw.
    public var offsets: Data?

    static func decode(record: ESMRecord) throws -> (Self, FieldTally) {
        var fields = try RecordFields(record: record, type: "WRLD")
        let decodedByWorldspace: [FourCC] = [
            "EDID", "FULL", "WNAM", "PNAM", "CNAM", "NAM2", "DNAM", "DATA", "ZNAM", "XEZN"
        ]
        for type in decodedByWorldspace {
            fields.markUsedAll(type)
        }
        var details = Self()
        details.largeReferences = fields.readAll("RNAM") { try WorldspaceLargeReferenceCell(&$0) }
        details.maxHeightData = fields.bytes("MHDT")
        details.fixedCenter = fields.read("WCTR") { try SIMD2($0.readInt16(), $0.readInt16()) }
        details.interiorLighting = fields.formID("LTMP")
        details.location = fields.formID("XLCN")
        details.lodWater = fields.formID("NAM3")
        details.lodWaterHeight = fields.float("NAM4")
        details.mapImage = fields.zstring("ICON")
        details.cloudModel = fields.model()
        details.map = fields.read("MNAM") { try WorldspaceMapData(&$0) }
        details.mapOffset = fields.read("ONAM") { reader in
            try WorldspaceMapOffset(scale: reader.readFloat32(), offset: reader.readFloat3())
        }
        details.distantLODMultiplier = fields.float("NAMA")
        details.boundsMin = fields.read("NAM0") { try SIMD2($0.readFloat32(), $0.readFloat32()) }
        details.boundsMax = fields.read("NAM9") { try SIMD2($0.readFloat32(), $0.readFloat32()) }
        details.canopyShadow = fields.zstring("NNAM")
        details.waterNoiseTexture = fields.zstring("XNAM")
        details.waterEnvironmentMap = fields.zstring("XWEM")
        details.hdLODDiffuseTexture = fields.zstring("TNAM")
        details.hdLODNormalTexture = fields.zstring("UNAM")
        details.offsets = fields.bytes("OFST")
        return (details, fields.finish())
    }
}
