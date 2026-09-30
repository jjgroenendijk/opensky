// Weather data index: the decoded WTHR/CLMT/REGN store, the weighted candidate
// value, and the deterministic generator the pick rolls with. The selection
// rules live in the engine, in WeatherSelection.swift, because a climate chance
// can come from a global variable.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import simd

/// One weighted weather candidate, unifying CLMT WLST and REGN RDWT entries.
nonisolated public struct WeightedWeather: Equatable, Sendable {
    public let weather: FormID
    public let chance: Int

    public init(weather: FormID, chance: Int) {
        self.weather = weather
        self.chance = chance
    }
}

/// Data-driven shortcuts used by the main-app precipitation acceptance
/// surface. Preferred vanilla editor IDs keep the visual gate reproducible;
/// classification fallback keeps the controls useful with other data sets.
nonisolated public enum WeatherPreset: CaseIterable, Sendable {
    case clear
    case rain
    case snow

    fileprivate var preferredEditorID: String {
        switch self {
        case .clear: "SkyrimClear"
        case .rain: "SkyrimOvercastRainFF"
        case .snow: "SkyrimStormSnow"
        }
    }

    fileprivate func matches(_ classification: Weather.Precipitation) -> Bool {
        switch self {
        case .clear: classification != .rainy && classification != .snow
        case .rain: classification == .rainy
        case .snow: classification == .snow
        }
    }
}

/// Decoded WTHR/CLMT/REGN index plus worldspace climate links, built once from
/// an ESMFile. Holds only value types after construction (no ESMFile
/// reference), so it is safe to read from the render thread while the cell
/// builder drives the same ESMFile on its own queue.
nonisolated public final class WeatherStore {
    public let weathers: [UInt32: Weather]
    public let climates: [UInt32: Climate]
    public let regions: [UInt32: Region]
    /// WRLD FormID -> CNAM climate FormID.
    public let worldspaceClimate: [UInt32: FormID]
    /// WRLD editor ID -> FormID, to resolve the pinned worldspace by name.
    public let worldspaceByEditorID: [String: UInt32]
    public let skippedRecords: SkippedRecords

    public init(file: ESMFile) {
        let localized = (try? file.pluginHeader().isLocalized) ?? false
        var skipped = SkippedRecords()
        weathers = Self.index(file, "WTHR", &skipped) { try Weather(record: $0) }
        climates = Self.index(file, "CLMT", &skipped) { try Climate(record: $0) }
        regions = Self.index(file, "REGN", &skipped) { try Region(record: $0) }
        var climateByWorld: [UInt32: FormID] = [:]
        var worldByEditorID: [String: UInt32] = [:]
        if let top = file.topGroup(of: "WRLD"), let children = try? top.children() {
            for case let .record(record) in children where record.type == "WRLD" {
                guard
                    let world = skipped.decode(
                        record,
                        using: { try Worldspace(record: $0, localized: localized) }
                    )
                else { continue }
                if let climate = world.climate, !climate.isNull {
                    climateByWorld[record.formID] = climate
                }
                if let editorID = world.editorID {
                    worldByEditorID[editorID] = record.formID
                }
            }
        }
        worldspaceClimate = climateByWorld
        worldspaceByEditorID = worldByEditorID
        skippedRecords = skipped
    }

    public func weather(_ id: FormID) -> Weather? {
        weathers[id.rawValue]
    }

    public func climate(_ id: FormID) -> Climate? {
        climates[id.rawValue]
    }

    public func region(_ id: FormID) -> Region? {
        regions[id.rawValue]
    }

    /// Weathers with usable visuals, sorted by editor ID — the UI force list.
    public func selectableWeathers() -> [Weather] {
        weathers.values
            .filter { $0.colors != nil }
            .sorted {
                ($0.editorID ?? $0.formID.description) < ($1.editorID ?? $1.formID.description)
            }
    }

    /// Stable rain/snow/clear candidates for the app's quick controls.
    /// Exact known vanilla records win; otherwise select the first sorted WTHR
    /// with the required decoded classification.
    public func weather(for preset: WeatherPreset) -> Weather? {
        let selectable = selectableWeathers()
        return selectable.first { $0.editorID == preset.preferredEditorID }
            ?? selectable.first { weather in
                preset.matches(weather.data?.precipitation ?? .none)
            }
    }

    private static func index<Value>(
        _ file: ESMFile,
        _ type: FourCC,
        _ skipped: inout SkippedRecords,
        _ decode: (ESMRecord) throws -> Value
    ) -> [UInt32: Value] {
        var out: [UInt32: Value] = [:]
        guard let top = file.topGroup(of: type), let children = try? top.children() else {
            return out
        }
        for case let .record(record) in children where record.type == type {
            if let value = skipped.decode(record, using: decode) {
                out[record.formID] = value
            }
        }
        return out
    }
}

/// SplitMix64: tiny deterministic PRNG for reproducible weather rolls. Seed
/// combines worldspace FormID + a reroll epoch counter so a given epoch always
/// picks the same weather (tests depend on it).
nonisolated public struct SplitMix64: Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
