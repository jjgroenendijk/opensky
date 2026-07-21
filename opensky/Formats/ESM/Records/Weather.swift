// WTHR weather record decoded into the fields the sky needs: per-time-of-day
// color layers (NAM0), fog distances (FNAM), and the DATA block's wind,
// precipitation, and lightning parameters. Cloud textures, cloud-layer
// colors/alphas (PNAM/JNAM), sounds (SNAM/TNAM), image spaces (IMSP),
// directional-ambient lighting (DALC), and static/spell/effect refs are
// intentionally skipped — milestone 7.2.1 does not consume them.
//
// Reference: UESP "Skyrim Mod:Mod File Format/WTHR"
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/WTHR
// Cross-checked against xEdit dev-4.1.5 Core/wbDefinitionsTES5.pas WTHR
// (wbWeatherColors / DATA / FNAM). Layout documented in docs/formats/weather.md.

import Foundation
import simd

nonisolated struct Weather {
    /// One NAM0 color layer: same RGB tint at each time of day. Values 0-1
    /// (source is RGBX bytes; the X pad byte is dropped, like WaterType).
    struct Colors: Equatable {
        let sunrise: SIMD3<Float>
        let day: SIMD3<Float>
        let sunset: SIMD3<Float>
        let night: SIMD3<Float>
    }

    /// NAM0 component index -> meaning. Order per UESP/xEdit wbWeatherColors.
    /// skyrim.esm omits trailing entries, so a record may carry only the first
    /// 13 or 14 of these; count derives from data size (16 bytes each).
    enum Component: Int, CaseIterable {
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
    struct FogDistances: Equatable {
        let dayNear: Float
        let dayFar: Float
        let nightNear: Float
        let nightFar: Float
        let dayPow: Float?
        let nightPow: Float?
        let dayMax: Float?
        let nightMax: Float?
    }

    /// Weather classification, derived from the DATA flags low nibble. At most
    /// one bit is set; absent -> none. Raw flags kept in `WeatherData.flags`.
    enum Precipitation {
        case none
        case pleasant
        case cloudy
        case rainy
        case snow
    }

    /// DATA block. uint8 fields the CK shows as floats are pre-scaled here;
    /// see per-field ranges. thunderFrequency kept raw (255 = low, 15 = high).
    struct WeatherData: Equatable {
        let windSpeed: Float // 0-1
        let transDelta: Float // 0-0.25
        let sunGlare: Float // 0-1
        let sunDamage: Float // 0-1
        let precipitationBeginFadeIn: Float // 0-1
        let precipitationEndFadeOut: Float // 0-1
        let thunderBeginFadeIn: Float // 0-1
        let thunderEndFadeOut: Float // 0-1
        let thunderFrequency: UInt8 // raw: 255 low .. 15 high
        let flags: UInt8 // raw classification/effect bitfield
        let lightningColor: SIMD3<Float> // 0-1 RGB
        let windDirection: Float // degrees, 0-360
        let windDirectionRange: Float // degrees, 0-180

        /// Classification from the low-nibble flag bits (UESP: at most one set).
        var precipitation: Precipitation {
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

    let formID: FormID
    let editorID: String?
    /// NAM0 layers indexed by `Component.rawValue`. nil when NAM0 absent or an
    /// unrecognised (non-16-multiple) size. May be shorter than Component.count.
    let colors: [Colors]?
    /// FNAM fog distances. nil when absent or an unrecognised size.
    let fog: FogDistances?
    /// DATA block. nil when absent or not the known 19-byte SSE size.
    let data: WeatherData?

    init(record: ESMRecord) throws {
        guard record.type == "WTHR" else {
            throw ESMError.malformed("expected WTHR record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var editorID: String?
        var colors: [Colors]?
        var fog: FogDistances?
        var data: WeatherData?
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
            default:
                break // cloud/sound/lighting/ref fields skipped (see header)
            }
        }
        self.editorID = editorID
        self.colors = colors
        self.fog = fog
        self.data = data
    }

    /// Layer for a named component, nil if the record omitted that index.
    func colors(for component: Component) -> Colors? {
        guard let colors, component.rawValue < colors.count else { return nil }
        return colors[component.rawValue]
    }

    var skyUpper: Colors? {
        colors(for: .skyUpper)
    }

    var skyLower: Colors? {
        colors(for: .skyLower)
    }

    var horizon: Colors? {
        colors(for: .horizon)
    }

    var ambient: Colors? {
        colors(for: .ambient)
    }

    var sun: Colors? {
        colors(for: .sun)
    }

    var sunGlare: Colors? {
        colors(for: .sunGlare)
    }

    var stars: Colors? {
        colors(for: .stars)
    }

    var fogNear: Colors? {
        colors(for: .fogNear)
    }

    var fogFar: Colors? {
        colors(for: .fogFar)
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
