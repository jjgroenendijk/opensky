// Env-gated weather-record sweep over the user's own Skyrim SE install
// (read-only external input, never committed — AGENTS.md Legal & IP): decodes
// every WTHR, CLMT, and REGN record in Skyrim.esm and asserts the whole set
// parses with sane values. Skips automatically when OPENSKY_DATA_ROOT is
// unset/unresolvable (CI has no game data). Summary printed + written to logs/.

import Foundation
@testable import opensky
import Testing

struct WeatherRealDataTests {
    /// Real data only when explicitly pointed at via the env var; the
    /// locator's Steam-default fallback is deliberately not consulted so
    /// machines without the override skip deterministically.
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    @Test(.enabled(if: Self.dataRoot != nil))
    func sweepsEveryWeatherClimateAndRegion() throws {
        let root = try #require(Self.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))

        let weathers = try sweepWeathers(in: file)
        #expect(!weathers.isEmpty, "no WTHR records in Skyrim.esm")
        let climates = try sweepClimates(in: file, weatherIDs: weathers.ids)
        #expect(!climates.isEmpty, "no CLMT records in Skyrim.esm")
        #expect(climates.unresolved == 0, "CLMT WLST references missing WTHR records")
        let regions = try sweepRegions(in: file, weatherIDs: weathers.ids)
        #expect(!regions.isEmpty, "no REGN records in Skyrim.esm")
        #expect(regions.unresolved == 0, "REGN RDWT references missing WTHR records")

        // WeatherStore builds the runtime index off the same file: Tamriel's
        // WRLD CNAM must resolve to a decoded CLMT (no hardcoded FormIDs).
        let store = WeatherStore(file: file)
        let tamriel = try #require(
            store.worldspaceByEditorID[FirstRenderCell.worldspaceEditorID],
            "no Tamriel worldspace in Skyrim.esm"
        )
        let climateID = try #require(
            store.worldspaceClimate[tamriel], "Tamriel WRLD carries no CNAM climate"
        )
        #expect(store.climate(climateID) != nil, "Tamriel CNAM does not resolve to a CLMT")
        #expect(!store.selectableWeathers().isEmpty)

        let layers = weathers.layerHistogram.sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }.joined(separator: " ")
        let classes = weathers.classHistogram.sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }.joined(separator: " ")
        let summary = """
        [INFO] Skyrim.esm weather sweep: \(weathers.records) WTHR, \
        \(climates.records) CLMT, \(regions.records) REGN decoded, no throws
        [INFO] WTHR NAM0 layer-count histogram (layers:records): \(layers)
        [INFO] WTHR classification histogram: \(classes); \
        DATA missing: \(weathers.dataMissing); DALC present: \(weathers.dalcPresent)
        [INFO] CLMT WLST entries: \(climates.entries) (unresolved \(climates.unresolved)); \
        timing missing: \(climates.timingMissing)
        [INFO] REGN with weather areas: \(regions.weatherRegions)/\(regions.records), \
        RDWT entries: \(regions.entries) (unresolved \(regions.unresolved))
        """
        print(summary)
        try? summary.write(to: logURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Per-type sweeps

    private struct WeatherStats {
        var records = 0
        var ids = Set<UInt32>()
        var layerHistogram: [Int: Int] = [:] // NAM0 layer count -> records
        var classHistogram: [String: Int] = [:]
        var dataMissing = 0
        var dalcPresent = 0
        var isEmpty: Bool {
            records == 0
        }
    }

    private func sweepWeathers(in file: ESMFile) throws -> WeatherStats {
        var stats = WeatherStats()
        for record in records(ofType: "WTHR", in: file) {
            let weather = try Weather(record: record)
            stats.records += 1
            stats.ids.insert(record.formID)
            stats.layerHistogram[weather.colors?.count ?? 0, default: 0] += 1
            if let data = weather.data {
                stats.classHistogram["\(data.precipitation)", default: 0] += 1
                #expect((0 ... 1).contains(data.windSpeed))
                #expect((0 ... 360).contains(data.windDirection))
            } else {
                stats.dataMissing += 1
            }
            if let fog = weather.fog {
                #expect(fog.dayNear.isFinite && fog.dayFar.isFinite)
            }
            if let ambient = weather.directionalAmbient {
                stats.dalcPresent += 1
                // Every DALC channel is a 0-1 RGBX byte color; the Scale float
                // must at least be finite.
                for keyframe in [ambient.sunrise, ambient.day, ambient.sunset, ambient.night] {
                    #expect((0 ... 1).contains(keyframe.colors.positiveZ.z))
                    #expect(keyframe.scale.isFinite)
                }
            }
        }
        return stats
    }

    private struct ClimateStats {
        var records = 0
        var entries = 0
        var unresolved = 0
        var timingMissing = 0
        var isEmpty: Bool {
            records == 0
        }
    }

    private func sweepClimates(in file: ESMFile, weatherIDs: Set<UInt32>) throws -> ClimateStats {
        var stats = ClimateStats()
        for record in records(ofType: "CLMT", in: file) {
            let climate = try Climate(record: record)
            stats.records += 1
            stats.entries += climate.weatherList.count
            stats.unresolved += climate.weatherList
                .count { !weatherIDs.contains($0.weather.rawValue) }
            if climate.timing == nil {
                stats.timingMissing += 1
            }
        }
        return stats
    }

    private struct RegionStats {
        var records = 0
        var weatherRegions = 0
        var entries = 0
        var unresolved = 0
        var isEmpty: Bool {
            records == 0
        }
    }

    private func sweepRegions(in file: ESMFile, weatherIDs: Set<UInt32>) throws -> RegionStats {
        var stats = RegionStats()
        for record in records(ofType: "REGN", in: file) {
            let region = try Region(record: record)
            stats.records += 1
            guard !region.weatherList.isEmpty else { continue }
            stats.weatherRegions += 1
            stats.entries += region.weatherList.count
            stats.unresolved += region.weatherList
                .count { !weatherIDs.contains($0.weather.rawValue) }
        }
        return stats
    }

    /// Records under the top-level group of `type` (WTHR/CLMT/REGN all live in
    /// flat top groups — no nested walk needed).
    private func records(ofType type: FourCC, in file: ESMFile) -> [ESMRecord] {
        guard
            let top = file.topGroup(of: type),
            let children = try? top.children()
        else { return [] }
        var result: [ESMRecord] = []
        for case let .record(record) in children where record.type == type {
            result.append(record)
        }
        return result
    }

    /// logs/weather-sweep.log (gitignored) next to the other real-data sidecars.
    private var logURL: URL {
        logsDirectory.appending(path: "weather-sweep.log")
    }

    private var logsDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // openskyTests/
            .deletingLastPathComponent() // repo root
            .appending(path: "logs")
    }
}
