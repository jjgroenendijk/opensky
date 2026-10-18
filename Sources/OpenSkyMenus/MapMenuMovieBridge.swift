// The measured AS2 contract of `Interface\map.swf`. The root timeline makes `WorldMap`,
// a `Map.MapMenu`. The engine calls `Init`, then `SetNumMarkers(n)`, writes
// `MarkerData` as `[name, icon, undiscovered]` per marker, and calls `CreateMarkers`
// until it has built them all, 10 per call. Each frame `MarkerData` is
// `[shown, x, y, rotation]` per marker on a 0 to 1 stage, and `RefreshMarkers` places
// them. See docs/engine/world-map.md#map-movie.

import Foundation
import OpenSkyFormatsSWF

/// A call the map movie makes.
nonisolated public enum MapMovieEvent: Equatable, Sendable {
    case marker(Int)
    case toggleLocalMap
    case journal
    case playerLocation
}

/// One marker as the movie draws it.
nonisolated public struct MapMovieMarker: Equatable, Sendable {
    public let name: String
    /// Index into the movie's `IconTypes`, which follows the `TNAM` marker types.
    public let iconType: Int
    public let isUndiscovered: Bool

    public init(name: String, iconType: Int, isUndiscovered: Bool) {
        self.name = name
        self.iconType = iconType
        self.isUndiscovered = isUndiscovered
    }
}

nonisolated public enum MapMenuMovieBridge: Sendable {
    public static let moviePath = "interface\\map.swf"
    public static let menuName = "WorldMap"
    public static let markersPerCreate = 10
    public static let sinkHostFunctions = [
        "PlaySound", "myLog", "ClickCallback", "SetLocalMapExtents"
    ]

    public static func prepare(
        runtime: SWFMovieRuntime,
        onEvent: @escaping @MainActor @Sendable (MapMovieEvent) -> Void
    ) {
        for name in sinkHostFunctions {
            runtime.registerHostFunction(name) { _ in .undefined }
        }
        runtime.registerHostFunction("MarkerClick") { call in
            guard case let .number(index)? = call.arguments.first, index.isFinite else {
                return .undefined
            }
            MainActor.assumeIsolated { onEvent(.marker(Int(index))) }
            return .undefined
        }
        let buttons: [(String, MapMovieEvent)] = [
            ("ToggleMapCallback", .toggleLocalMap), ("OpenJournalCallback", .journal),
            ("CurrentLocationCallback", .playerLocation)
        ]
        for (name, event) in buttons {
            runtime.registerHostFunction(name) { _ in
                MainActor.assumeIsolated { onEvent(event) }
                return .undefined
            }
        }
    }

    /// `Init` registers the movie's callbacks, so `SetDateString` follows it.
    public static func activate(date: String, runtime: SWFMovieRuntime) {
        call("Init", runtime: runtime)
        runtime.callMovie(
            "SetPlatform",
            arguments: [.number(SystemMenuMovieBridge.pcPlatform), .boolean(false)]
        )
        runtime.callMovie("SetDateString", arguments: [.string(date)])
    }

    public static func create(_ markers: [MapMovieMarker], runtime: SWFMovieRuntime) {
        call("SetNumMarkers", arguments: [.integer(markers.count)], runtime: runtime)
        writeMarkerData(markers.flatMap { marker in
            [
                .string(marker.name), .integer(marker.iconType),
                .boolean(marker.isUndiscovered)
            ]
        }, runtime: runtime)
        for _ in 0 ... markers.count / markersPerCreate {
            call("CreateMarkers", runtime: runtime)
        }
    }

    /// `points` holds each marker's place on the stage, 0 to 1, or nil when off screen.
    public static func refresh(
        _ points: [SIMD2<Float>?], selected: Int?, runtime: SWFMovieRuntime
    ) {
        writeMarkerData(points.flatMap { point -> [AS2Value] in
            guard let point else { return [.boolean(false), .number(0), .number(0), .number(0)] }
            return [.boolean(true), .number(Double(point.x)), .number(Double(point.y)), .number(0)]
        }, runtime: runtime)
        call("RefreshMarkers", runtime: runtime)
        call("SetSelectedMarker", arguments: [.integer(selected ?? -1)], runtime: runtime)
    }

    static func worldMap(runtime: SWFMovieRuntime) -> AS2Object? {
        runtime.root.object.lookup(menuName)?.property.value.objectValue
    }

    private static func writeMarkerData(_ values: [AS2Value], runtime: SWFMovieRuntime) {
        guard let map = worldMap(runtime: runtime) else { return }
        map.assign(.object(runtime.runtime.makeArray(values)), for: "MarkerData")
    }

    private static func call(
        _ name: String, arguments: [AS2Value] = [], runtime: SWFMovieRuntime
    ) {
        guard
            let map = worldMap(runtime: runtime),
            let function = map.lookup(name)?.property.value.functionValue
        else {
            runtime.runtime.noteMissing(name)
            return
        }
        runtime.markDirty()
        runtime.runtime.invoke(.object(function), thisValue: .object(map), arguments: arguments)
    }
}
