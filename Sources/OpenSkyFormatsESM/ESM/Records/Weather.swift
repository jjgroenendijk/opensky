// WTHR decoded into what the sky needs: NAM0 color layers, FNAM fog, DATA
// wind, precipitation and lightning, and the four DALC ambient keyframes
// (Sunrise, Day, Sunset, Night). Clouds, sounds and image spaces are skipped.
// Layout: docs/formats/weather.md.

import Foundation
import OpenSkyFormatsCore
import simd

nonisolated public struct Weather: Sendable {
    /// One NAM0 color layer: same RGB tint at each time of day. Values 0-1
    /// (source is RGBX bytes; the X pad byte is dropped, like WaterType).
    public struct Colors: Equatable, Sendable {
        public let sunrise: SIMD3<Float>
        public let day: SIMD3<Float>
        public let sunset: SIMD3<Float>
        public let night: SIMD3<Float>
    }

    /// NAM0 component index -> meaning. Order per UESP/xEdit wbWeatherColors.
    /// skyrim.esm omits trailing entries, so a record may carry only the first
    /// 13 or 14 of these; count derives from data size (16 bytes each).
    public enum Component: Int, CaseIterable, Sendable {
        case skyUpper = 0
        case fogNear = 1
        case unknownCloudLayer = 2 // ignored; overwritten by PNAM in-game
        case ambient = 3
        case sunlight = 4
        case sun = 5
        case stars = 6
        case skyLower = 7
        case horizon = 8
        case effectLighting = 9
        case cloudLODDiffuse = 10
        case cloudLODAmbient = 11
        case fogFar = 12
        case skyStatics = 13
        case waterMultiplier = 14
        case sunGlare = 15
        case moonGlare = 16
    }

    /// FNAM fog distances. Pow/max are nil for the legacy 16-byte (4-float)
    /// variant that carries only the near/far pairs.
    public struct FogDistances: Equatable, Sendable {
        public let dayNear: Float
        public let dayFar: Float
        public let nightNear: Float
        public let nightFar: Float
        public let dayPow: Float?
        public let nightPow: Float?
        public let dayMax: Float?
        public let nightMax: Float?
    }

    /// Weather classification, derived from the DATA flags low nibble. At most
    /// one bit is set; absent -> none. Raw flags kept in `WeatherData.flags`.
    public enum Precipitation: Equatable, Sendable {
        case none
        case pleasant
        case cloudy
        case rainy
        case snow
    }

    /// DATA block. uint8 fields the CK shows as floats are pre-scaled here;
    /// see per-field ranges. thunderFrequency kept raw (255 = low, 15 = high).
    public struct WeatherData: Equatable, Sendable {
        public let windSpeed: Float // 0-1
        public let transDelta: Float // 0-0.25
        public let sunGlare: Float // 0-1
        public let sunDamage: Float // 0-1
        public let precipitationBeginFadeIn: Float // 0-1
        public let precipitationEndFadeOut: Float // 0-1
        public let thunderBeginFadeIn: Float // 0-1
        public let thunderEndFadeOut: Float // 0-1
        public let thunderFrequency: UInt8 // raw: 255 low .. 15 high
        public let flags: UInt8 // raw classification/effect bitfield
        public let lightningColor: SIMD3<Float> // 0-1 RGB
        public let windDirection: Float // degrees, 0-360
        public let windDirectionRange: Float // degrees, 0-180

        /// Classification from the low-nibble flag bits (UESP: at most one set).
        public var precipitation: Precipitation {
            if flags & 0x01 != 0 {
                return .pleasant
            }
            if flags & 0x02 != 0 {
                return .cloudy
            }
            if flags & 0x04 != 0 {
                return .rainy
            }
            if flags & 0x08 != 0 {
                return .snow
            }
            return .none
        }
    }

    /// One DALC keyframe: the six-axis directional ambient plus the ambient
    /// specular color and the trailing float. xEdit labels the float "Scale";
    /// some community docs call it a fresnel/specular power. Colors are 0-1
    /// (RGBX bytes, pad dropped, like the NAM0 layers).
    public struct DirectionalAmbient: Equatable, Sendable {
        public let colors: DirectionalAmbientColors
        public let specular: SIMD3<Float>
        public let scale: Float
    }

    /// The four DALC keyframes a WTHR carries, one per time of day. Record
    /// order is Sunrise, Day, Sunset, Night (xEdit wbDefinitionsTES5 WTHR).
    public struct DirectionalAmbientKeyframes: Equatable, Sendable {
        public let sunrise: DirectionalAmbient
        public let day: DirectionalAmbient
        public let sunset: DirectionalAmbient
        public let night: DirectionalAmbient
    }

    public let formID: FormID
    public let editorID: String?
    /// NAM0 layers indexed by `Component.rawValue`. nil when NAM0 absent or an
    /// unrecognised (non-16-multiple) size. May be shorter than Component.count.
    public let colors: [Colors]?
    /// FNAM fog distances. nil when absent or an unrecognised size.
    public let fog: FogDistances?
    /// DATA block. nil when absent or not the known 19-byte SSE size.
    public let data: WeatherData?
    /// DALC directional ambient keyframes. nil when the record carries fewer
    /// than four 32-byte DALC subrecords (skipped rather than guessed).
    public let directionalAmbient: DirectionalAmbientKeyframes?

    public init(record: ESMRecord) throws {
        guard record.type == "WTHR" else {
            throw ESMError.malformed("expected WTHR record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var editorID: String?
        var colors: [Colors]?
        var fog: FogDistances?
        var data: WeatherData?
        // DALC subrecords stream in Sunrise/Day/Sunset/Night order; collect
        // them positionally and map the first four (see keyframes(from:)).
        var ambientFrames: [DirectionalAmbient] = []
        for field in try record.fields() {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "NAM0":
                colors = try Self.readColorLayers(&reader)
            case "FNAM":
                fog = try Self.readFog(&reader)
            case "DATA":
                data = try Self.readData(&reader)
            case "DALC":
                if let frame = try Self.readDirectionalAmbient(&reader) {
                    ambientFrames.append(frame)
                }
            default:
                break // cloud/sound/ref fields skipped (see header)
            }
        }
        self.editorID = editorID
        self.colors = colors
        self.fog = fog
        self.data = data
        directionalAmbient = Self.keyframes(from: ambientFrames)
    }

    // NAM0: array of 16-byte structs, each = sunrise/day/sunset/night RGBX.
    // Count varies (skyrim.esm drops trailing entries): 208/224/272 bytes seen.
    // Derive count from size; skip sizes not divisible by 16 rather than guess.
    private static func readColorLayers(_ reader: inout BinaryReader) throws -> [Colors]? {
        let count = reader.data.count
        guard count > 0, count % 16 == 0 else { return nil }
        var layers: [Colors] = []
        for _ in 0 ..< (count / 16) {
            try layers.append(Colors(
                sunrise: readColor(&reader),
                day: readColor(&reader),
                sunset: readColor(&reader),
                night: readColor(&reader)
            ))
        }
        return layers
    }

    // FNAM: 32-byte (8-float) SSE structure; legacy 16-byte (4-float) variant
    // carries only the near/far pairs. Other sizes skipped.
    private static func readFog(_ reader: inout BinaryReader) throws -> FogDistances? {
        let count = reader.data.count
        guard count == 32 || count == 16 else { return nil }
        let dayNear = try reader.readFloat32()
        let dayFar = try reader.readFloat32()
        let nightNear = try reader.readFloat32()
        let nightFar = try reader.readFloat32()
        guard count == 32 else {
            return FogDistances(
                dayNear: dayNear, dayFar: dayFar, nightNear: nightNear, nightFar: nightFar,
                dayPow: nil, nightPow: nil, dayMax: nil, nightMax: nil
            )
        }
        return try FogDistances(
            dayNear: dayNear, dayFar: dayFar, nightNear: nightNear, nightFar: nightFar,
            dayPow: reader.readFloat32(), nightPow: reader.readFloat32(),
            dayMax: reader.readFloat32(), nightMax: reader.readFloat32()
        )
    }

    // DATA: 19-byte SSE structure. Bytes 1-2 and the two Visual Effect bytes
    // (15-16) are unused here. Unknown sizes skipped (no throw) per UESP.
    private static func readData(_ reader: inout BinaryReader) throws -> WeatherData? {
        guard reader.data.count == 19 else { return nil }
        let windSpeed = try Float(reader.readUInt8()) / 255
        _ = try reader.read(count: 2) // unknown, always 0
        let transDelta = try Float(reader.readUInt8()) / 255 * 0.25
        let sunGlare = try Float(reader.readUInt8()) / 255
        let sunDamage = try Float(reader.readUInt8()) / 255
        let precipBeginFadeIn = try Float(reader.readUInt8()) / 255
        let precipEndFadeOut = try Float(reader.readUInt8()) / 255
        let thunderBeginFadeIn = try Float(reader.readUInt8()) / 255
        let thunderEndFadeOut = try Float(reader.readUInt8()) / 255
        let thunderFrequency = try reader.readUInt8()
        let flags = try reader.readUInt8()
        let lightningColor = try readRGB(&reader)
        _ = try reader.read(count: 2) // Visual Effect begin/end, unused here
        // uint8 -> degrees: full byte range maps to the CK's 0-360 / 0-180.
        let windDirection = try Float(reader.readUInt8()) / 255 * 360
        let windDirectionRange = try Float(reader.readUInt8()) / 255 * 180
        return WeatherData(
            windSpeed: windSpeed,
            transDelta: transDelta,
            sunGlare: sunGlare,
            sunDamage: sunDamage,
            precipitationBeginFadeIn: precipBeginFadeIn,
            precipitationEndFadeOut: precipEndFadeOut,
            thunderBeginFadeIn: thunderBeginFadeIn,
            thunderEndFadeOut: thunderEndFadeOut,
            thunderFrequency: thunderFrequency,
            flags: flags,
            lightningColor: lightningColor,
            windDirection: windDirection,
            windDirectionRange: windDirectionRange
        )
    }

    // DALC: 32-byte wbAmbientColors. Six directional RGBX colors (X+/X-/Y+/Y-/
    // Z+/Z-), one Specular RGBX, one float Scale. Undersized/unknown DALC ->
    // nil (skip rather than guess), matching the record's decode policy.
    private static func readDirectionalAmbient(
        _ reader: inout BinaryReader
    ) throws -> DirectionalAmbient? {
        guard reader.data.count >= 32 else { return nil }
        let colors = try DirectionalAmbientColors(
            positiveX: readColor(&reader),
            negativeX: readColor(&reader),
            positiveY: readColor(&reader),
            negativeY: readColor(&reader),
            positiveZ: readColor(&reader),
            negativeZ: readColor(&reader)
        )
        let specular = try readColor(&reader)
        let scale = try reader.readFloat32()
        return DirectionalAmbient(colors: colors, specular: specular, scale: scale)
    }

    /// Maps the first four DALC keyframes to Sunrise/Day/Sunset/Night. Fewer
    /// than four -> nil: a partial set has no defined time-of-day mapping.
    private static func keyframes(
        from frames: [DirectionalAmbient]
    ) -> DirectionalAmbientKeyframes? {
        guard frames.count >= 4 else { return nil }
        return DirectionalAmbientKeyframes(
            sunrise: frames[0], day: frames[1], sunset: frames[2], night: frames[3]
        )
    }

    /// RGBX color: three channels 0-255 then one pad byte (dropped).
    private static func readColor(_ reader: inout BinaryReader) throws -> SIMD3<Float> {
        let color = try readRGB(&reader)
        _ = try reader.readUInt8() // RGBX padding
        return color
    }

    /// Bare RGB triple, no pad (DATA lightning color).
    private static func readRGB(_ reader: inout BinaryReader) throws -> SIMD3<Float> {
        let red = try Float(reader.readUInt8()) / 255
        let green = try Float(reader.readUInt8()) / 255
        let blue = try Float(reader.readUInt8()) / 255
        return SIMD3(red, green, blue)
    }
}

/// Named NAM0 component accessors, in an extension so they stay off the struct's
/// body-length budget.
nonisolated extension Weather {
    /// Layer for a named component, nil if the record omitted that index.
    public func colors(for component: Component) -> Colors? {
        guard let colors, component.rawValue < colors.count else { return nil }
        return colors[component.rawValue]
    }

    public var skyUpper: Colors? {
        colors(for: .skyUpper)
    }

    public var horizon: Colors? {
        colors(for: .horizon)
    }

    public var sunGlare: Colors? {
        colors(for: .sunGlare)
    }
}
