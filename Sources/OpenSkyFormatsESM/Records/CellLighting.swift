// CELL XCLL and LGTM lighting layouts. Inherit flags are resolved by
// CellSceneBuilderLighting, not here. Layout: docs/formats/lighting.md.

import Foundation
import OpenSkyFormatsCore
import simd

nonisolated public struct DirectionalAmbientColors: Equatable, Sendable {
    public let positiveX: SIMD3<Float>
    public let negativeX: SIMD3<Float>
    public let positiveY: SIMD3<Float>
    public let negativeY: SIMD3<Float>
    public let positiveZ: SIMD3<Float>
    public let negativeZ: SIMD3<Float>

    public init(
        positiveX: SIMD3<Float>,
        negativeX: SIMD3<Float>,
        positiveY: SIMD3<Float>,
        negativeY: SIMD3<Float>,
        positiveZ: SIMD3<Float>,
        negativeZ: SIMD3<Float>
    ) {
        self.positiveX = positiveX
        self.negativeX = negativeX
        self.positiveY = positiveY
        self.negativeY = negativeY
        self.positiveZ = positiveZ
        self.negativeZ = negativeZ
    }

    public static let black = DirectionalAmbientColors(
        positiveX: .zero,
        negativeX: .zero,
        positiveY: .zero,
        negativeY: .zero,
        positiveZ: .zero,
        negativeZ: .zero
    )
}

nonisolated public struct CellLightingValues: Equatable, Sendable {
    public struct InheritFlags: OptionSet, Equatable, Sendable {
        public let rawValue: UInt32

        public init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        public static let ambientColor = InheritFlags(rawValue: 0x0001)
        public static let directionalColor = InheritFlags(rawValue: 0x0002)
        public static let fogColor = InheritFlags(rawValue: 0x0004)
        public static let fogNear = InheritFlags(rawValue: 0x0008)
        public static let fogFar = InheritFlags(rawValue: 0x0010)
        public static let directionalRotation = InheritFlags(rawValue: 0x0020)
        public static let directionalFade = InheritFlags(rawValue: 0x0040)
        public static let fogClipDistance = InheritFlags(rawValue: 0x0080)
        public static let fogPower = InheritFlags(rawValue: 0x0100)
        public static let fogMax = InheritFlags(rawValue: 0x0200)
        public static let lightFadeDistances = InheritFlags(rawValue: 0x0400)
    }

    public let ambientColor: SIMD3<Float>
    public let directionalColor: SIMD3<Float>
    public let fogNearColor: SIMD3<Float>
    public let fogNear: Float
    public let fogFar: Float
    /// Integer degrees. Vanilla probe: Whiterun interior template uses 180.
    public let directionalRotationXY: Int32
    public let directionalRotationZ: Int32
    public let directionalFade: Float
    public let fogClipDistance: Float
    public let fogPower: Float
    /// Optional tail: truncated XCLL variants stop at or within this block.
    public let directionalAmbient: DirectionalAmbientColors?
    public let fogFarColor: SIMD3<Float>?
    public let fogMax: Float?
    public let lightFadeBegin: Float?
    public let lightFadeEnd: Float?
    public let inherits: InheritFlags

    public init(
        ambientColor: SIMD3<Float>,
        directionalColor: SIMD3<Float>,
        fogNearColor: SIMD3<Float>,
        fogNear: Float,
        fogFar: Float,
        directionalRotationXY: Int32,
        directionalRotationZ: Int32,
        directionalFade: Float,
        fogClipDistance: Float,
        fogPower: Float,
        directionalAmbient: DirectionalAmbientColors?,
        fogFarColor: SIMD3<Float>?,
        fogMax: Float?,
        lightFadeBegin: Float?,
        lightFadeEnd: Float?,
        inherits: InheritFlags
    ) {
        self.ambientColor = ambientColor
        self.directionalColor = directionalColor
        self.fogNearColor = fogNearColor
        self.fogNear = fogNear
        self.fogFar = fogFar
        self.directionalRotationXY = directionalRotationXY
        self.directionalRotationZ = directionalRotationZ
        self.directionalFade = directionalFade
        self.fogClipDistance = fogClipDistance
        self.fogPower = fogPower
        self.directionalAmbient = directionalAmbient
        self.fogFarColor = fogFarColor
        self.fogMax = fogMax
        self.lightFadeBegin = lightFadeBegin
        self.lightFadeEnd = lightFadeEnd
        self.inherits = inherits
    }

    /// XCLL/LGTM share their first 88 bytes. Byte 88 is XCLL inheritance;
    /// LGTM reserves it. Fields from byte 40 onward are optional so known
    /// truncated variants decode without shifting later offsets.
    public static func decode(_ data: Data, hasInheritFlags: Bool) throws -> CellLightingValues? {
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

    public func replacingDirectionalAmbient(
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

    public static func decodeDirectionalAmbient(_ data: Data) throws -> DirectionalAmbientColors? {
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

nonisolated public struct LightingTemplate: Sendable {
    public let formID: FormID
    public let editorID: String?
    public let values: CellLightingValues
    public let skipped: FieldTally

    public init(record: ESMRecord) throws {
        guard record.type == "LGTM" else {
            throw ESMError.malformed("expected LGTM record, got \(record.type)")
        }
        formID = FormID(record.formID)
        var editorID: String?
        var values: CellLightingValues?
        var directionalAmbient: DirectionalAmbientColors?
        var skipped = FieldTally()
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
                skipped.note(.unknownField(field.type))
            }
        }
        self.skipped = skipped
        guard let values else {
            throw ESMError.malformed("LGTM \(formID) has no usable DATA field")
        }
        self.editorID = editorID
        self.values = values.replacingDirectionalAmbient(directionalAmbient)
    }
}
