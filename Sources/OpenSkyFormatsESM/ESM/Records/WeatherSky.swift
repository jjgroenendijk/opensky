// The WTHR fields beyond color, fog, DATA and DALC: 32 cloud layers, sounds,
// sky statics, and the linked image spaces, precipitation and lighting.
// Layout and sources: docs/formats/weather.md.

import Foundation
import OpenSkyFormatsCore

/// Four values, one per time of day.
nonisolated public struct TimeOfDayValues<Value: Equatable & Sendable>: Equatable, Sendable {
    public let sunrise: Value
    public let day: Value
    public let sunset: Value
    public let night: Value
}

nonisolated public struct WeatherCloudLayer: Equatable, Sendable {
    public let index: Int
    public var texture: String?
    /// RNAM and QNAM, raw bytes. 127 means no movement.
    public var speedY: UInt8?
    public var speedX: UInt8?
    /// PNAM, RGBA bytes per time of day.
    public var colors: TimeOfDayValues<SIMD4<UInt8>>?
    /// JNAM.
    public var alphas: TimeOfDayValues<Float>?
    /// From NAM1.
    public var isDisabled = false
}

nonisolated public struct WeatherSound: Equatable, Sendable {
    public let sound: FormID?
    /// 0 default, 1 precipitation, 2 wind, 3 thunder.
    public let type: UInt32
}

nonisolated public struct WeatherSky: Equatable, Sendable {
    public let cloudLayers: [WeatherCloudLayer]
    /// LNAM.
    public let maxCloudLayers: UInt32?
    /// MNAM, an SPGD.
    public let precipitation: FormID?
    /// NNAM, an RFCT.
    public let visualEffect: FormID?
    public let sounds: [WeatherSound]
    /// TNAM, STAT records.
    public let skyStatics: [FormID]
    /// IMSP, IMGS records.
    public let imageSpaces: TimeOfDayValues<FormID?>?
    /// HNAM, VOLI records.
    public let volumetricLighting: TimeOfDayValues<FormID?>?
    /// NAM2 and NAM3.
    public let sunGlare: TimeOfDayValues<SIMD4<UInt8>>?
    public let moonGlare: TimeOfDayValues<SIMD4<UInt8>>?
    public let auroraModel: ModelData?
    /// DNAM, CNAM, ANAM, BNAM: textures of the older 4-layer cloud set.
    public let legacyCloudTextures: [String]
    /// ONAM, the older 4-layer speeds. xEdit marks it unused.
    public let legacyCloudSpeeds: Data?

    init(_ fields: inout RecordFields) {
        maxCloudLayers = fields.uint32("LNAM")
        precipitation = fields.formID("MNAM")
        visualEffect = fields.formID("NNAM")
        sounds = fields.readAll("SNAM") { reader in
            try WeatherSound(sound: reader.readFormID().nonNull, type: reader.readUInt32())
        }
        skyStatics = fields.formIDs("TNAM")
        imageSpaces = fields.read("IMSP") { try Self.formIDs(&$0) }
        volumetricLighting = fields.read("HNAM") { try Self.formIDs(&$0) }
        sunGlare = fields.read("NAM2") { try Self.byteColors(&$0) }
        moonGlare = fields.read("NAM3") { try Self.byteColors(&$0) }
        auroraModel = fields.model()
        legacyCloudTextures = ["DNAM", "CNAM", "ANAM", "BNAM"].compactMap { fields.zstring($0) }
        legacyCloudSpeeds = fields.bytes("ONAM")
        cloudLayers = Self.cloudLayers(&fields)
    }

    /// The layer a cloud texture signature names.
    /// `00TX` to `@0TX` are 0 to 16, `A0TX` to `O0TX` are 17 to 31.
    static func cloudLayerIndex(_ signature: FourCC) -> Int? {
        guard signature.rawValue >> 8 == FourCC("\00TX").rawValue >> 8 else { return nil }
        let first = Int(UInt8(truncatingIfNeeded: signature.rawValue))
        switch first {
        case 0x30 ... 0x40: return first - 0x30
        case 0x41 ... 0x4F: return first - 0x41 + 17
        default: return nil
        }
    }

    private static func cloudLayers(_ fields: inout RecordFields) -> [WeatherCloudLayer] {
        var layers = (0 ..< 32).map { WeatherCloudLayer(index: $0) }
        for index in fields.fields.indices where !fields.isUsed(at: index) {
            guard let layer = cloudLayerIndex(fields.fields[index].type) else { continue }
            layers[layer].texture = fields.read(at: index) { try $0.readZString() }
        }
        let speedY = fields.read("RNAM") { try $0.read(count: $0.bytesRemaining) } ?? Data()
        let speedX = fields.read("QNAM") { try $0.read(count: $0.bytesRemaining) } ?? Data()
        let colors = fields.read("PNAM") { try repeated(&$0, stride: 16, byteColors) } ?? []
        let alphas = fields.read("JNAM") { try repeated(&$0, stride: 16, floats) } ?? []
        let disabled = fields.uint32("NAM1") ?? 0
        for index in layers.indices {
            layers[index].speedY = index < speedY.count ? speedY[speedY.startIndex + index] : nil
            layers[index].speedX = index < speedX.count ? speedX[speedX.startIndex + index] : nil
            layers[index].colors = index < colors.count ? colors[index] : nil
            layers[index].alphas = index < alphas.count ? alphas[index] : nil
            layers[index].isDisabled = disabled & (1 << UInt32(index)) != 0
        }
        return layers
    }

    private static func repeated<Value>(
        _ reader: inout BinaryReader,
        stride: Int,
        _ decode: (inout BinaryReader) throws -> Value
    ) throws -> [Value] {
        var values: [Value] = []
        while reader.bytesRemaining >= stride {
            try values.append(decode(&reader))
        }
        return values
    }

    private static func formIDs(_ reader: inout BinaryReader) throws -> TimeOfDayValues<FormID?> {
        try TimeOfDayValues(
            sunrise: reader.readFormID().nonNull, day: reader.readFormID().nonNull,
            sunset: reader.readFormID().nonNull, night: reader.readFormID().nonNull
        )
    }

    private static func floats(_ reader: inout BinaryReader) throws -> TimeOfDayValues<Float> {
        try TimeOfDayValues(
            sunrise: reader.readFloat32(), day: reader.readFloat32(),
            sunset: reader.readFloat32(), night: reader.readFloat32()
        )
    }

    private static func byteColors(_ reader: inout BinaryReader) throws
        -> TimeOfDayValues<SIMD4<UInt8>>
    {
        try TimeOfDayValues(
            sunrise: color(&reader), day: color(&reader), sunset: color(&reader),
            night: color(&reader)
        )
    }

    private static func color(_ reader: inout BinaryReader) throws -> SIMD4<UInt8> {
        try SIMD4(reader.readUInt8(), reader.readUInt8(), reader.readUInt8(), reader.readUInt8())
    }
}
