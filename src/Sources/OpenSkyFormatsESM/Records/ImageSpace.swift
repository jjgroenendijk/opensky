// IMGS image space: the HDR, cinematic, tint, and depth-of-field values a
// weather or cell applies to the frame. Layout and sources: docs/formats/image-spaces.md.

import Foundation
public import OpenSkyFormatsCore

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

        /// The word is the high half of a float 2 + 4n, n 0 to 15: n / 2 is the blur
        /// radius 0 to 7, and an odd n keeps the sky sharp (docs/formats/image-spaces.md).
        var blurCode: Int? {
            guard let skyBlurRadius else { return nil }
            let value = Float(bitPattern: UInt32(skyBlurRadius) << 16)
            guard value.isFinite else { return nil }
            let code = ((value - 2) / 4).rounded()
            return (0 ... 15).contains(code) ? Int(code) : nil
        }

        /// 0 to 7, as the Creation Kit's depth of field "Blur Radius".
        public var blurRadius: Int? {
            blurCode.map { $0 / 2 }
        }

        /// The Creation Kit's "No Sky": the sky stays sharp.
        public var keepsSkySharp: Bool? {
            blurCode.map { $0 % 2 == 1 }
        }
    }

    public let formID: FormID
    public let editorID: String?
    public let hdr: HDR?
    public let cinematic: Cinematic?
    public let tint: Tint?
    public let depthOfField: DepthOfField?
    public let skipped: FieldTally

    public init(record: ESMRecord) throws {
        var fields = try RecordFields(record: record, type: "IMGS")
        formID = fields.formID
        editorID = fields.editorID()
        var hdr: HDR?
        var cinematic: Cinematic?
        var tint: Tint?
        // Field order matters: the older ENAM block and the newer fields set the
        // same values, and the later one wins (docs/formats/image-spaces.md).
        for index in fields.fields.indices where !fields.isUsed(at: index) {
            switch fields.fields[index].type {
            case "ENAM":
                if let older = fields.read(at: index, { try Self.olderBlock(&$0) }) {
                    let values = Self.values(of: older, keeping: hdr)
                    hdr = values.hdr
                    cinematic = values.cinematic
                    tint = values.tint
                }
            case "HNAM":
                hdr = fields.read(at: index) { try HDR(&$0) }
            case "CNAM":
                cinematic = fields.read(at: index) {
                    try Cinematic(
                        saturation: $0.readFloat32(),
                        brightness: $0.readFloat32(),
                        contrast: $0.readFloat32()
                    )
                }
            case "TNAM":
                tint = fields.read(at: index) {
                    try Tint(amount: $0.readFloat32(), color: $0.readFloat3())
                }
            default:
                continue
            }
        }
        self.hdr = hdr
        self.cinematic = cinematic
        self.tint = tint
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

nonisolated extension ImageSpace {
    private static func olderBlock(_ reader: inout BinaryReader) throws -> [Float] {
        try (0 ..< 14).map { _ in try reader.readFloat32() }
    }

    /// ENAM: floats 0-3 HDR, 4 both receive-bloom threshold and white, 5-6 the
    /// light scales, 7-9 cinematic, 10-13 tint. Eye-adapt strength is kept.
    private struct OlderValues {
        let hdr: HDR
        let cinematic: Cinematic
        let tint: Tint
    }

    private static func values(of older: [Float], keeping hdr: HDR?) -> OlderValues {
        let newHDR = HDR(
            eyeAdaptSpeed: older[0], bloomBlurRadius: older[1], bloomThreshold: older[2],
            bloomScale: older[3], receiveBloomThreshold: older[4], white: older[4],
            sunlightScale: older[5], skyScale: older[6],
            eyeAdaptStrength: hdr?.eyeAdaptStrength ?? 0
        )
        return OlderValues(
            hdr: newHDR,
            cinematic: Cinematic(saturation: older[7], brightness: older[8], contrast: older[9]),
            tint: Tint(amount: older[10], color: SIMD3(older[11], older[12], older[13]))
        )
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
