// SPGD precipitation particles, VOLI volumetric lighting, and MATO directional
// material (the snow and moss layer on statics). Layout and sources:
// docs/formats/environment-shading.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct ShaderParticleGeometry: Equatable, Sendable {
    /// DATA: 40 bytes in the original game, 48 in SE.
    public struct Properties: Equatable, Sendable {
        public let gravityVelocity: Float
        public let rotationVelocity: Float
        public let particleSize: SIMD2<Float>
        public let centerOffsetMinimum: Float
        public let centerOffsetMaximum: Float
        public let initialRotationRange: Float
        public let subtextureCount: SIMD2<UInt32>
        /// 0 rain, 1 snow.
        public let type: UInt32
        public let boxSize: UInt32?
        public let particleDensity: Float?
        public let size: Int
    }

    public let formID: FormID
    public let editorID: String?
    public let properties: Properties?
    /// ICON, the particle texture.
    public let texturePath: String?
    public let skipped: FieldTally

    public init(record: ESMRecord) throws {
        var fields = try RecordFields(record: record, type: "SPGD")
        formID = fields.formID
        editorID = fields.editorID()
        properties = fields.read("DATA") { try Properties(&$0) }
        texturePath = fields.zstring("ICON")
        skipped = fields.finish()
    }
}

nonisolated extension ShaderParticleGeometry.Properties {
    init(_ reader: inout BinaryReader) throws {
        size = reader.bytesRemaining
        gravityVelocity = try reader.readFloat32()
        rotationVelocity = try reader.readFloat32()
        particleSize = try SIMD2(reader.readFloat32(), reader.readFloat32())
        centerOffsetMinimum = try reader.readFloat32()
        centerOffsetMaximum = try reader.readFloat32()
        initialRotationRange = try reader.readFloat32()
        subtextureCount = try SIMD2(reader.readUInt32(), reader.readUInt32())
        type = try reader.readUInt32()
        boxSize = reader.bytesRemaining >= 4 ? try reader.readUInt32() : nil
        particleDensity = reader.bytesRemaining >= 4 ? try reader.readFloat32() : nil
    }
}

nonisolated public struct VolumetricLighting: Equatable, Sendable {
    public let formID: FormID
    public let editorID: String?
    /// CNAM.
    public let intensity: Float?
    /// DNAM.
    public let customColorContribution: Float?
    /// ENAM, FNAM, GNAM: red, green, blue.
    public let color: SIMD3<Float>?
    /// HNAM.
    public let densityContribution: Float?
    /// INAM.
    public let densitySize: Float?
    /// JNAM.
    public let densityWindSpeed: Float?
    /// KNAM.
    public let densityFallingSpeed: Float?
    /// LNAM.
    public let phaseFunctionContribution: Float?
    /// MNAM.
    public let phaseFunctionScattering: Float?
    /// NNAM, at most 1.
    public let samplingRangeFactor: Float?
    public let skipped: FieldTally

    public init(record: ESMRecord) throws {
        var fields = try RecordFields(record: record, type: "VOLI")
        formID = fields.formID
        editorID = fields.editorID()
        intensity = fields.float("CNAM")
        customColorContribution = fields.float("DNAM")
        let red = fields.float("ENAM")
        let green = fields.float("FNAM")
        let blue = fields.float("GNAM")
        color = red.flatMap { red in green.flatMap { green in blue.map { SIMD3(red, green, $0) } } }
        densityContribution = fields.float("HNAM")
        densitySize = fields.float("INAM")
        densityWindSpeed = fields.float("JNAM")
        densityFallingSpeed = fields.float("KNAM")
        phaseFunctionContribution = fields.float("LNAM")
        phaseFunctionScattering = fields.float("MNAM")
        samplingRangeFactor = fields.float("NNAM")
        skipped = fields.finish()
    }
}

nonisolated public struct MaterialObject: Equatable, Sendable {
    /// DATA: 28 bytes at least; later form versions add the tail members.
    public struct Properties: Equatable, Sendable {
        public let falloffScale: Float
        public let falloffBias: Float
        public let noiseUVScale: Float
        public let materialUVScale: Float
        public let projectionVector: SIMD3<Float>
        public let normalDampener: Float?
        public let singlePassColor: SIMD3<Float>?
        public let isSinglePass: Bool?
        public let isSnow: Bool?
        public let size: Int
    }

    public let formID: FormID
    public let editorID: String?
    public let model: ModelData?
    /// DNAM property blocks. xEdit does not decode them, so they stay raw.
    public let propertyData: [Data]
    public let properties: Properties?
    public let skipped: FieldTally

    public init(record: ESMRecord) throws {
        var fields = try RecordFields(record: record, type: "MATO")
        formID = fields.formID
        editorID = fields.editorID()
        model = fields.model()
        propertyData = fields.readAll("DNAM") { try $0.read(count: $0.bytesRemaining) }
        properties = fields.read("DATA") { try Properties(&$0) }
        skipped = fields.finish()
    }
}

nonisolated extension MaterialObject.Properties {
    init(_ reader: inout BinaryReader) throws {
        size = reader.bytesRemaining
        falloffScale = try reader.readFloat32()
        falloffBias = try reader.readFloat32()
        noiseUVScale = try reader.readFloat32()
        materialUVScale = try reader.readFloat32()
        projectionVector = try reader.readFloat3()
        normalDampener = reader.bytesRemaining >= 4 ? try reader.readFloat32() : nil
        singlePassColor = reader.bytesRemaining >= 12 ? try reader.readFloat3() : nil
        isSinglePass = reader.bytesRemaining >= 4 ? try reader.readUInt32() != 0 : nil
        isSnow = reader.bytesRemaining >= 4 ? try reader.readUInt32() != 0 : nil
    }
}
