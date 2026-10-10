// IMGS image space: the HDR, cinematic, tint, and depth-of-field values a
// weather or cell applies to the frame. Layout and sources: docs/formats/image-spaces.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct ImageSpace: Equatable, Sendable {
    /// HNAM, nine floats.
    public struct HDR: Equatable, Sendable {
        public let eyeAdaptSpeed: Float
        public let bloomBlurRadius: Float
        public let bloomThreshold: Float
        public let bloomScale: Float
        public let receiveBloomThreshold: Float
        public let white: Float
        public let sunlightScale: Float
        public let skyScale: Float
        public let eyeAdaptStrength: Float
    }

    /// CNAM.
    public struct Cinematic: Equatable, Sendable {
        public let saturation: Float
        public let brightness: Float
        public let contrast: Float
    }

    /// TNAM: amount, then a float RGB color.
    public struct Tint: Equatable, Sendable {
        public let amount: Float
        public let color: SIMD3<Float>
    }

    /// DNAM, 16 bytes, or 12 without the sky and blur-radius word.
    public struct DepthOfField: Equatable, Sendable {
        public let strength: Float
        public let distance: Float
        public let range: Float
        /// The packed sky and blur-radius code; xEdit lists 16 known values.
        public let skyBlurRadius: UInt16?
    }

    public let formID: FormID
    public let editorID: String?
    /// ENAM, the legacy 56-byte block, kept as its 14 floats.
    public let legacyData: [Float]?
    public let hdr: HDR?
    public let cinematic: Cinematic?
    public let tint: Tint?
    public let depthOfField: DepthOfField?
    public let skipped: FieldTally

    public init(record: ESMRecord) throws {
        var fields = try RecordFields(record: record, type: "IMGS")
        formID = fields.formID
        editorID = fields.editorID()
        legacyData = fields.read("ENAM") { reader in
            try (0 ..< 14).map { _ in try reader.readFloat32() }
        }
        hdr = fields.read("HNAM") { try HDR(&$0) }
        cinematic = fields.read("CNAM") {
            try Cinematic(
                saturation: $0.readFloat32(),
                brightness: $0.readFloat32(),
                contrast: $0.readFloat32()
            )
        }
        tint = fields.read("TNAM") { try Tint(amount: $0.readFloat32(), color: $0.readFloat3()) }
        depthOfField = fields.read("DNAM") { reader in
            let strength = try reader.readFloat32()
            let distance = try reader.readFloat32()
            let range = try reader.readFloat32()
            var radius: UInt16?
            if reader.bytesRemaining >= 4 {
                reader.skip(2)
                radius = try reader.readUInt16()
            }
            return DepthOfField(
                strength: strength,
                distance: distance,
                range: range,
                skyBlurRadius: radius
            )
        }
        skipped = fields.finish()
    }
}

nonisolated extension ImageSpace.HDR {
    init(_ reader: inout BinaryReader) throws {
        eyeAdaptSpeed = try reader.readFloat32()
        bloomBlurRadius = try reader.readFloat32()
        bloomThreshold = try reader.readFloat32()
        bloomScale = try reader.readFloat32()
        receiveBloomThreshold = try reader.readFloat32()
        white = try reader.readFloat32()
        sunlightScale = try reader.readFloat32()
        skyScale = try reader.readFloat32()
        eyeAdaptStrength = try reader.readFloat32()
    }
}
