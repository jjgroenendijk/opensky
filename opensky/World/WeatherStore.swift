// Weather data index + region/climate selection (M7.2.2), split from
// WeatherRuntime (file-length limits): the decoded WTHR/CLMT/REGN store, the
// weighted candidate rules, and the deterministic pick. Pure over the store so
// selection unit-tests without a running renderer.
//
// Selection follows xEdit REGN semantics (RDAT weather area priority + override
// flag) with the worldspace CLMT (WRLD CNAM) as fallback; see
// docs/engine/weather.md.

import Foundation

/// One weighted weather candidate, unifying CLMT WLST and REGN RDWT entries.
nonisolated struct WeightedWeather: Equatable {
    let weather: FormID
    let chance: Int
}

/// Decoded WTHR/CLMT/REGN index plus worldspace climate links, built once from
/// an ESMFile. Holds only value types after construction (no ESMFile
/// reference), so it is safe to read from the render thread while the cell
/// builder drives the same ESMFile on its own queue.
nonisolated final class WeatherStore {
    let weathers: [UInt32: Weather]
    let climates: [UInt32: Climate]
    let regions: [UInt32: Region]
    /// WRLD FormID -> CNAM climate FormID.
    let worldspaceClimate: [UInt32: FormID]
    /// WRLD editor ID -> FormID, to resolve the pinned worldspace by name.
    let worldspaceByEditorID: [String: UInt32]

    init(file: ESMFile) {
        let localized = (try? file.pluginHeader().isLocalized) ?? false
        weathers = Self.index(file, "WTHR") { try? Weather(record: $0) }
        climates = Self.index(file, "CLMT") { try? Climate(record: $0) }
        regions = Self.index(file, "REGN") { try? Region(record: $0) }
        var climateByWorld: [UInt32: FormID] = [:]
        var worldByEditorID: [String: UInt32] = [:]
        if let top = file.topGroup(of: "WRLD"), let children = try? top.children() {
            for case let .record(record) in children where record.type == "WRLD" {
                guard let world = try? Worldspace(record: record, localized: localized) else {
                    continue
                }
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
    }

    func weather(_ id: FormID) -> Weather? {
        weathers[id.rawValue]
    }

    func climate(_ id: FormID) -> Climate? {
        climates[id.rawValue]
    }

    func region(_ id: FormID) -> Region? {
        regions[id.rawValue]
    }

    /// Weathers with usable visuals, sorted by editor ID — the UI force list.
    func selectableWeathers() -> [Weather] {
        weathers.values
            .filter { $0.colors != nil }
            .sorted {
                ($0.editorID ?? $0.formID.description) < ($1.editorID ?? $1.formID.description)
            }
    }

    private static func index<Value>(
        _ file: ESMFile,
        _ type: FourCC,
        _ decode: (ESMRecord) -> Value?
    ) -> [UInt32: Value] {
        var out: [UInt32: Value] = [:]
        guard let top = file.topGroup(of: type), let children = try? top.children() else {
            return out
        }
        for case let .record(record) in children where record.type == type {
            if let value = decode(record) {
                out[record.formID] = value
            }
        }
        return out
    }
}

/// Region/climate selection: builds the weighted candidate pool for a location
/// and picks one deterministically. Pure over a WeatherStore so it unit-tests
/// without a running renderer.
nonisolated enum WeatherSelection {
    /// Candidate pool for `worldspace` given the exterior cell's XCLR regions.
    ///
    /// Rules (xEdit REGN semantics, flagged in docs/engine/weather.md):
    /// - Applicable regions = XCLR regions with a weather area whose WNAM is
    ///   this worldspace (or unset). Highest RDAT weather priority wins ties.
    /// - The winning region's RDWT list is the base pool. When its weather-area
    ///   Override flag is clear, the worldspace climate list is appended as
    ///   lower-priority candidates; when set, the region list stands alone.
    /// - No applicable region -> the worldspace climate (WRLD CNAM) list.
    static func candidates(
        worldspace: UInt32?,
        regionIDs: [FormID],
        store: WeatherStore
    ) -> [WeightedWeather] {
        let applicable = regionIDs
            .compactMap { store.region($0) }
            .filter { region in
                guard !region.weatherList.isEmpty else { return false }
                guard let owner = region.worldspace, !owner.isNull else { return true }
                return worldspace == nil || owner.rawValue == worldspace
            }
            .sorted { ($0.weatherPriority ?? 0) > ($1.weatherPriority ?? 0) }

        var pool: [WeightedWeather] = []
        if let winner = applicable.first {
            pool = winner.weatherList
                .map { WeightedWeather(weather: $0.weather, chance: $0.chance) }
            if !winner.weatherOverride {
                pool += climateCandidates(worldspace: worldspace, store: store)
            }
        } else {
            pool = climateCandidates(worldspace: worldspace, store: store)
        }
        return pool.filter { store.weather($0.weather) != nil }
    }

    static func climateCandidates(worldspace: UInt32?, store: WeatherStore) -> [WeightedWeather] {
        guard
            let worldspace,
            let climateID = store.worldspaceClimate[worldspace],
            let climate = store.climate(climateID)
        else { return [] }
        return climate.weatherList.map { WeightedWeather(weather: $0.weather, chance: $0.chance) }
    }

    /// Weighted pick by `chance`. Zero/negative chances are ignored; an
    /// all-zero pool falls back to a uniform pick so a candidate always wins.
    static func pick(from pool: [WeightedWeather], seed: UInt64) -> FormID? {
        guard !pool.isEmpty else { return nil }
        var rng = SplitMix64(seed: seed)
        let total = pool.reduce(0) { $0 + max(0, $1.chance) }
        guard total > 0 else {
            return pool[Int(rng.next() % UInt64(pool.count))].weather
        }
        var roll = Int(rng.next() % UInt64(total))
        for candidate in pool {
            roll -= max(0, candidate.chance)
            if roll < 0 {
                return candidate.weather
            }
        }
        return pool.last?.weather
    }
}

/// SplitMix64: tiny deterministic PRNG for reproducible weather rolls. Seed
/// combines worldspace FormID + a reroll epoch counter so a given epoch always
/// picks the same weather (tests depend on it).
nonisolated struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
