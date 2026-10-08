// WATR water. DNAM gives the colors and the surface fields the water shader reads;
// the rest stays opaque. Layout and sources: docs/formats/water.md.

import Foundation
import OpenSkyFormatsCore
import simd

nonisolated public struct WaterType: Sendable {
    public struct Colors: Equatable, Sendable {
        public let shallow: SIMD3<Float>
        public let deep: SIMD3<Float>
        public let reflection: SIMD3<Float>

        public init(shallow: SIMD3<Float>, deep: SIMD3<Float>, reflection: SIMD3<Float>) {
            self.shallow = shallow
            self.deep = deep
            self.reflection = reflection
        }
    }

    public let formID: FormID
    public let editorID: String?
    /// DNAM colors. nil for absent or unknown-size DNAM variants.
    public let colors: Colors?
    /// DNAM surface fields. nil exactly when `colors` is nil.
    public let surface: WaterSurfaceFields?
    /// The fields the water renderer does not read yet.
    public let details: WaterDetails
    public let skipped: FieldTally

    /// Decodes with FULL read as inline text.
    public init(record: ESMRecord) throws {
        try self.init(record: record, localized: false)
    }

    public init(record: ESMRecord, localized: Bool) throws {
        guard record.type == "WATR" else {
            throw ESMError.malformed("expected WATR record, got \(record.type)")
        }
        var rest = try RecordFields(record: record, type: "WATR", localized: localized)
        let recordID = rest.formID
        formID = recordID

        var editorID: String?
        var colors: Colors?
        var surface: WaterSurfaceFields?
        try rest.readEach { field in
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "DNAM":
                // SSE carries 228-byte and 232-byte variants. Both share the
                // first 52 bytes: ten floats, then shallow/deep/reflection
                // RGBX colors. Unknown variants are skipped, never guessed.
                guard field.data.count == 228 || field.data.count == 232 else { return true }
                _ = try reader.read(count: 40)
                colors = try Colors(
                    shallow: Self.readColor(&reader),
                    deep: Self.readColor(&reader),
                    reflection: Self.readColor(&reader)
                )
                surface = try WaterSurfaceFields(dnam: field.data)
            default:
                return false
            }
            return true
        }
        details = WaterDetails(&rest)
        skipped = rest.finish()
        self.editorID = editorID
        self.colors = colors
        self.surface = surface
    }

    private static func readColor(_ reader: inout BinaryReader) throws -> SIMD3<Float> {
        let red = try Float(reader.readUInt8()) / 255
        let green = try Float(reader.readUInt8()) / 255
        let blue = try Float(reader.readUInt8()) / 255
        _ = try reader.readUInt8() // RGBX padding
        return SIMD3(red, green, blue)
    }
}

/// WATR fields beside DNAM. xEdit dev-4.1.6 `WATR`; docs/formats/water.md.
nonisolated public struct WaterDetails: Equatable, Sendable {
    public let name: LString?
    /// NNAM x3 — noise textures from older versions.
    public let oldNoiseTextures: [String]
    /// ANAM — opacity, 0-100.
    public let opacity: UInt8?
    /// FNAM — bit 0 causes damage; SSE bit 3 enable flowmap, bit 4 blend normals.
    public let flags: UInt8
    /// MNAM — material ID xEdit marks unused, kept raw.
    public let unusedMaterialID: Data?
    public let material: FormID?
    public let openSound: FormID?
    public let spell: FormID?
    public let imageSpace: FormID?
    /// DATA — damage per second.
    public let damagePerSecond: UInt16?
    /// GNAM — daytime, nighttime, and underwater waters; xEdit marks them unused.
    public let relatedWaters: [FormID]
    /// NAM0/NAM1 — linear and angular velocity.
    public let linearVelocity: SIMD3<Float>?
    public let angularVelocity: SIMD3<Float>?
    /// NAM2-NAM4 noise layer textures, then NAM5 flow normals. Nil for an absent slot.
    public let noiseTextures: [String?]

    init(_ fields: inout RecordFields) {
        name = fields.lstring("FULL")
        oldNoiseTextures = fields.readAll("NNAM") { try $0.readZString() }
        opacity = fields.uint8("ANAM")
        flags = fields.uint8("FNAM") ?? 0
        unusedMaterialID = fields.bytes("MNAM")
        material = fields.formID("TNAM")
        openSound = fields.formID("SNAM")
        spell = fields.formID("XNAM")
        imageSpace = fields.formID("INAM")
        damagePerSecond = fields.uint16("DATA")
        relatedWaters = fields.formIDArray("GNAM")
        linearVelocity = fields.read("NAM0") { try $0.readFloat3() }
        angularVelocity = fields.read("NAM1") { try $0.readFloat3() }
        noiseTextures = ["NAM2", "NAM3", "NAM4", "NAM5"].map { fields.zstring($0) }
    }
}
