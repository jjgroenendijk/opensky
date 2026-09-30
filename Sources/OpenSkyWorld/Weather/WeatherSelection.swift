// Region/climate weather selection over a WeatherStore. Selection follows xEdit
// REGN semantics (RDAT weather area priority + override flag) with the
// worldspace CLMT (WRLD CNAM) as fallback; see docs/engine/weather.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState
import simd

/// Region/climate selection: builds the weighted candidate pool for a location
/// and picks one deterministically. Pure over a WeatherStore so it unit-tests
/// without a running renderer.
nonisolated public enum WeatherSelection: Sendable {
    /// Candidate pool for `worldspace` from the cell's XCLR regions (xEdit REGN
    /// semantics, docs/engine/weather.md). The highest RDAT priority region wins.
    /// Its RDWT list is the base pool; the climate list is appended unless the
    /// weather area's Override flag is set. No region -> the WRLD CNAM climate.
    /// A nil `globals` keeps every authored climate chance.
    public static func candidates(
        worldspace: UInt32?,
        regionIDs: [FormID],
        store: WeatherStore,
        globals: GlobalResolution? = nil
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
                pool += climateCandidates(worldspace: worldspace, store: store, globals: globals)
            }
        } else {
            pool = climateCandidates(worldspace: worldspace, store: store, globals: globals)
        }
        return pool.filter { store.weather($0.weather) != nil }
    }

    /// The worldspace climate's WLST entries as weighted candidates. A resolved
    /// GLOB replaces the static chance; an unresolved one keeps it. No spec says
    /// what the game does here, so this is OpenSky's choice
    /// (docs/formats/weather.md).
    public static func climateCandidates(
        worldspace: UInt32?,
        store: WeatherStore,
        globals: GlobalResolution? = nil
    ) -> [WeightedWeather] {
        guard
            let worldspace,
            let climateID = store.worldspaceClimate[worldspace],
            let climate = store.climate(climateID)
        else { return [] }
        return climate.weatherList.map { entry in
            WeightedWeather(
                weather: entry.weather,
                chance: resolvedChance(entry, globals: globals)
            )
        }
    }

    /// The chance a WLST entry contributes: its global's current value when one
    /// resolves, the authored chance otherwise. Non-finite and fractional
    /// global values are rounded and clamped into a usable non-negative weight,
    /// because `pick(from:seed:)` sums these.
    private static func resolvedChance(
        _ entry: Climate.WeatherChance,
        globals: GlobalResolution?
    ) -> Int {
        guard
            let globals,
            let id = entry.global,
            let value = globals.floatValue(for: id),
            value.isFinite
        else { return entry.chance }
        // Clamped to Int32 before conversion: a mod (or a script) can put any
        // float in a global, and `Int(_: Float)` traps past Int.max.
        let rounded = value.rounded(.toNearestOrAwayFromZero)
        return Int(simd_clamp(rounded, 0, Float(Int32.max)))
    }

    /// Weighted pick by `chance`. Zero/negative chances are ignored; an
    /// all-zero pool falls back to a uniform pick so a candidate always wins.
    public static func pick(from pool: [WeightedWeather], seed: UInt64) -> FormID? {
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
