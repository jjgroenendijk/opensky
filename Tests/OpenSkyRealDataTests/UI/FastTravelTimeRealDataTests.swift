// Fast travel time between town map markers against the times measured in the
// original game. Table: Elder Scrolls wiki "Fast Travel (Skyrim)", in game hours,
// wearing light armor. A city without a marker of its own name is timed from its
// stables, beside the gate. See docs/engine/world-map.md.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyMenus
import OpenSkyPhysics
@testable import OpenSkyWorld
import simd
import Testing

struct FastTravelTimeRealDataTests {
    static let towns = [
        "Dawnstar", "Ivarstead", "Markarth", "Morthal", "Riften",
        "Riverwood", "Solitude", "Whiterun", "Windhelm", "Winterhold"
    ]
    /// Upper triangle of the wiki table, row by row.
    static let measuredHours: [[Double]] = [
        [12, 15, 5, 17, 10, 6, 7.5, 9, 5.5],
        [18, 12, 7, 4, 15.5, 6, 8, 11.5],
        [10, 24, 14, 10, 13, 21.5, 20],
        [19, 9, 4, 6, 12, 11],
        [11, 21, 12, 9, 14],
        [12, 3, 10, 12],
        [10, 15, 13],
        [9, 10],
        [6]
    ]

    /// The table rounds to half hours, which is 25% of a 2 hour trip.
    static let routeTolerance = 0.2
    static let meanTolerance = 0.05

    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func tripTimesMatchTheMeasuredTable() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let strings = LocalizedStrings(vfs: VirtualFileSystem(root: root), pluginName: "Skyrim.esm")
        let markers = MapMarkerIndex(plugins: [("Skyrim.esm", file)])
            .markers(in: ResolvedFormID(plugin: "Skyrim.esm", objectID: 0x3C))
        var places: [String: SIMD3<Float>] = [:]
        for town in Self.towns {
            let stables = "\(town) Stables"
            places[town] = (markers.first { strings.resolve($0.name) == town }
                ?? markers.first { strings.resolve($0.name) == stables })?.position
        }
        let missing = Self.towns.filter { places[$0] == nil }
        let settings = GameSettingLoader.load(root: root, baseFile: file)
        let types = MovementTypeStore(plugins: [("Skyrim.esm", file)])
        let walk = PlayerMovementConfiguration.resolve(store: settings, movementTypes: types)
            .travelSpeed.value
        let multiplier = MenuMapSettings(store: settings).fastTravelSpeedMultiplier

        var lines = [
            "walk \(walk) multiplier \(multiplier)", "missing \(missing)",
            "route\tunits\tmeasured\topensky\tratio"
        ]
        var distanceSquares = 0.0
        var distanceHours = 0.0
        var ratios: [Double] = []
        for (row, hours) in Self.measuredHours.enumerated() {
            for (offset, measured) in hours.enumerated() {
                let from = Self.towns[row], to = Self.towns[row + 1 + offset]
                guard let start = places[from], let end = places[to] else { continue }
                let distance = simd_distance(start, end)
                let opensky = FastTravelRule.gameSeconds(
                    distance: distance, walkSpeed: walk, speedMultiplier: multiplier, timeScale: 20
                ) / 3600
                ratios.append(opensky / measured)
                distanceSquares += Double(distance * distance)
                distanceHours += Double(distance) * measured
                lines.append(String(
                    format: "%@-%@\t%.0f\t%.1f\t%.2f\t%.3f", from, to, distance, measured, opensky,
                    opensky / measured
                ))
            }
        }
        // Least squares for hours = distance * k, so the speed is timeScale / (3600 k).
        let perUnit = distanceHours > 0 ? distanceSquares / distanceHours : 0
        lines.append(String(format: "fitted speed %.2f units per second", perUnit * 20 / 3600))
        let dir = try RepositoryLogs.createdDirectory("fast-travel-time")
        try lines.joined(separator: "\n").write(
            to: dir.appending(path: "routes.tsv"), atomically: true, encoding: .utf8
        )
        let mean = ratios.reduce(0, +) / Double(max(ratios.count, 1))
        #expect(missing == ["Solitude"], "see \(dir.path)/routes.tsv")
        #expect(abs(mean - 1) < Self.meanTolerance, "mean ratio \(mean)")
        #expect(
            ratios.allSatisfy { abs($0 - 1) < Self.routeTolerance },
            "see \(dir.path)/routes.tsv"
        )
    }
}
