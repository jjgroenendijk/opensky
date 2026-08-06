// CELL XCLL + LGTM DATA/DALC lighting layouts. Values stay decoupled from
// renderer policy; CellSceneBuilderLighting resolves XCLL inherit flags.
//
// References:
// - UESP CELL/LGTM: https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/CELL
// - xEdit dev-4.1.6 wbDefinitionsTES5.pas, CELL XCLL + LGTM
// - xEdit dev-4.1.6 wbDefinitionsCommon.pas, wbAmbientColors

import Foundation
import simd

nonisolated struct DirectionalAmbientColors: Equatable {
    let positiveX: SIMD3<Float>
    let negativeX: SIMD3<Float>
    let positiveY: SIMD3<Float>
    let negativeY: SIMD3<Float>
    let positiveZ: SIMD3<Float>
    let negativeZ: SIMD3<Float>

    static let black = DirectionalAmbientColors(
        positiveX: .zero,
        negativeX: .zero,
        positiveY: .zero,
        negativeY: .zero,
        positiveZ: .zero,
        negativeZ: .zero
    )
}

nonisolated struct CellLightingValues: Equatable {
    struct InheritFlags: OptionSet, Equatable {
        let rawValue: UInt32

        static let ambientColor = InheritFlags(rawValue: 0x0001)
        static let directionalColor = InheritFlags(rawValue: 0x0002)
        static let fogColor = InheritFlags(rawValue: 0x0004)
        static let fogNear = InheritFlags(rawValue: 0x0008)
        static let fogFar = InheritFlags(rawValue: 0x0010)
        static let directionalRotation = InheritFlags(rawValue: 0x0020)
        static let directionalFade = InheritFlags(rawValue: 0x0040)
        static let fogClipDistance = InheritFlags(rawValue: 0x0080)
        static let fogPower = InheritFlags(rawValue: 0x0100)
        static let fogMax = InheritFlags(rawValue: 0x0200)
        static let lightFadeDistances = InheritFlags(rawValue: 0x0400)
    }

    let ambientColor: SIMD3<Float>
    let directionalColor: SIMD3<Float>
    let fogNearColor: SIMD3<Float>
    let fogNear: Float
    let fogFar: Float
    /// Integer degrees. Vanilla probe: Whiterun interior template uses 180.
    let directionalRotationXY: Int32
    let directionalRotationZ: Int32
    let directionalFade: Float
    let fogClipDistance: Float
    let fogPower: Float
    /// Optional tail: truncated XCLL variants stop at or within this block.
    let directionalAmbient: DirectionalAmbientColors?
    let fogFarColor: SIMD3<Float>?
    let fogMax: Float?
    let lightFadeBegin: Float?
    let lightFadeEnd: Float?
    let inherits: InheritFlags

    /// XCLL/LGTM share their first 88 bytes. Byte 88 is XCLL inheritance;
    /// LGTM reserves it. Fields from byte 40 onward are optional so known
    /// truncated variants decode without shifting later offsets.
    static func decode(_ data: Data, hasInheritFlags: Bool) throws -> CellLightingValues? {
        guard data.count >= 40 else { return nil }
        var reader = BinaryReader(data)
        let ambientColor = try readColor(&reader)
        let directionalColor = try readColor(&reader)
        let fogNearColor = try readColor(&reader)
        let fogNear = try reader.readFloat32()
        let fogFar = try reader.readFloat32()
        let directionalRotationXY = try Int32(bitPattern: reader.readUInt32())
        let directionalRotationZ = try Int32(bitPattern: reader.readUInt32())
        let directionalFade = try reader.readFloat32()
        let fogClipDistance = try reader.readFloat32()
        let fogPower = try reader.readFloat32()

        let directionalAmbient = try readDirectionalAmbientIfPresent(&reader)
        // SSE form version 34+ carries specular color + Fresnel power after
        // six directional RGBX colors. Renderer does not consume either yet.
        if reader.bytesRemaining >= 4 {
            reader.skip(4)
        }
        if reader.bytesRemaining >= 4 {
            reader.skip(4)
        }
        let fogFarColor = try readColorIfPresent(&reader)
        let fogMax = try readFloatIfPresent(&reader)
        let lightFadeBegin = try readFloatIfPresent(&reader)
        let lightFadeEnd = try readFloatIfPresent(&reader)
        let tail = try readUInt32IfPresent(&reader) ?? 0

        return CellLightingValues(
            ambientColor: ambientColor,
            directionalColor: directionalColor,
            fogNearColor: fogNearColor,
            fogNear: fogNear,
            fogFar: fogFar,
            directionalRotationXY: directionalRotationXY,
            directionalRotationZ: directionalRotationZ,
            directionalFade: directionalFade,
            fogClipDistance: fogClipDistance,
            fogPower: fogPower,
            directionalAmbient: directionalAmbient,
            fogFarColor: fogFarColor,
            fogMax: fogMax,
            lightFadeBegin: lightFadeBegin,
            lightFadeEnd: lightFadeEnd,
            inherits: hasInheritFlags ? InheritFlags(rawValue: tail) : []
        )
    }

    func replacingDirectionalAmbient(
        _ colors: DirectionalAmbientColors?
    ) -> CellLightingValues {
        CellLightingValues(
            ambientColor: ambientColor,
            directionalColor: directionalColor,
            fogNearColor: fogNearColor,
            fogNear: fogNear,
            fogFar: fogFar,
            directionalRotationXY: directionalRotationXY,
            directionalRotationZ: directionalRotationZ,
            directionalFade: directionalFade,
            fogClipDistance: fogClipDistance,
            fogPower: fogPower,
            directionalAmbient: colors ?? directionalAmbient,
            fogFarColor: fogFarColor,
            fogMax: fogMax,
            lightFadeBegin: lightFadeBegin,
            lightFadeEnd: lightFadeEnd,
            inherits: inherits
        )
    }

    static func decodeDirectionalAmbient(_ data: Data) throws -> DirectionalAmbientColors? {
        var reader = BinaryReader(data)
        return try readDirectionalAmbientIfPresent(&reader)
    }

    private static func readDirectionalAmbientIfPresent(
        _ reader: inout BinaryReader
    ) throws -> DirectionalAmbientColors? {
        guard reader.bytesRemaining >= 24 else { return nil }
        return try DirectionalAmbientColors(
            positiveX: readColor(&reader),
            negativeX: readColor(&reader),
            positiveY: readColor(&reader),
            negativeY: readColor(&reader),
            positiveZ: readColor(&reader),
            negativeZ: readColor(&reader)
        )
    }

    private static func readColorIfPresent(
        _ reader: inout BinaryReader
    ) throws -> SIMD3<Float>? {
        guard reader.bytesRemaining >= 4 else { return nil }
        return try readColor(&reader)
    }

    private static func readColor(_ reader: inout BinaryReader) throws -> SIMD3<Float> {
        let red = try Float(reader.readUInt8()) / 255
        let green = try Float(reader.readUInt8()) / 255
        let blue = try Float(reader.readUInt8()) / 255
        _ = try reader.readUInt8()
        return SIMD3(red, green, blue)
    }

    private static func readFloatIfPresent(_ reader: inout BinaryReader) throws -> Float? {
        guard reader.bytesRemaining >= 4 else { return nil }
        return try reader.readFloat32()
    }

    private static func readUInt32IfPresent(_ reader: inout BinaryReader) throws -> UInt32? {
        guard reader.bytesRemaining >= 4 else { return nil }
        return try reader.readUInt32()
    }
}

nonisolated struct LightingTemplate {
    let formID: FormID
    let editorID: String?
    let values: CellLightingValues

    init(record: ESMRecord) throws {
        guard record.type == "LGTM" else {
            throw ESMError.malformed("expected LGTM record, got \(record.type)")
        }
        formID = FormID(record.formID)
        var editorID: String?
        var values: CellLightingValues?
        var directionalAmbient: DirectionalAmbientColors?
        for field in try record.fields() {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "DATA":
                values = try CellLightingValues.decode(field.data, hasInheritFlags: false)
            case "DALC":
                directionalAmbient = try CellLightingValues.decodeDirectionalAmbient(field.data)
            default:
                break
            }
        }
        guard let values else {
            throw ESMError.malformed("LGTM \(formID) has no usable DATA field")
        }
        self.editorID = editorID
        self.values = values.replacingDirectionalAmbient(directionalAmbient)
    }
}
