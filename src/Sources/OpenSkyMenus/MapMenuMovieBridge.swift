// The measured AS2 contract of `Interface\map.swf`. The root timeline makes `WorldMap`,
// a `Map.MapMenu`. The engine calls `Init`, then `SetNumMarkers(n)`, writes
// `MarkerData` as `[name, icon, undiscovered]` per marker, and calls `CreateMarkers`
// until it has built them all, 10 per call. Each frame `MarkerData` is
// `[shown, x, y, rotation]` per marker on a 0 to 1 stage, and `RefreshMarkers` places
// them. See docs/engine/world-map.md#map-movie.

import Foundation
import OpenSkyFormatsSWF

/// A call the map movie makes.
nonisolated enum MapMovieEvent: Equatable, Sendable {
    case marker(Int)
    case toggleLocalMap
    case journal
    case playerLocation
}

/// One marker as the movie draws it.
nonisolated struct MapMovieMarker: Equatable, Sendable {
    let name: String
    /// Index into the movie's `IconTypes`, which follows the `TNAM` marker types.
    let iconType: Int
    let isUndiscovered: Bool
}

nonisolated enum MapMenuMovieBridge: Sendable {
    static let moviePath = "interface\\map.swf"
    static let menuName = "WorldMap"
    static let markersPerCreate = 10
    /// `PlayerSetMarker` in the movie's `IconTypes`, after the 60 `TNAM` types and the
    /// door and quest icons.
    static let playerSetIconType = 65
    /// `YouAreHereMarker`, the last of `IconTypes`. The movie gives the marker of this type
    /// its `YouAreHereMarker` clip once `PlayerLocationMarkerType` names it.
    static let currentLocationIconType = 66
    static let sinkHostFunctions = [
        "PlaySound", "myLog", "ClickCallback", "SetLocalMapExtents"
    ]

    static func prepare(
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
    static func activate(date: String, runtime: SWFMovieRuntime) {
        call("Init", runtime: runtime)
        runtime.callMovie(
            "SetPlatform",
            arguments: [.number(SystemMenuMovieBridge.pcPlatform), .boolean(false)]
        )
        runtime.callMovie("SetDateString", arguments: [.string(date)])
    }

    static func create(_ markers: [MapMovieMarker], runtime: SWFMovieRuntime) {
        worldMap(runtime: runtime)?.assign(
            .integer(currentLocationIconType), for: "PlayerLocationMarkerType"
        )
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
    static func refresh(
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
        AS2Interpreter.invoke(
            in: runtime.runtime,
            .object(function),
            thisValue: .object(map),
            arguments: arguments
        )
    }
}
