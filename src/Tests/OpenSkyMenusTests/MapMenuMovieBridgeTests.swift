// The map movie contract on a synthetic `WorldMap` object: marker creation in steps of
// 10, the per-frame `MarkerData` layout, and the movie's calls.

import Foundation
import OpenSkyFormatsSWF
@testable import OpenSkyMenus
import Testing

@MainActor
struct MapMenuMovieBridgeTests {
    private static func worldMap(
        _ runtime: SWFMovieRuntime
    ) -> (map: AS2Object, calls: MenuMovieEventLog<String>) {
        let map = runtime.runtime.makeObject()
        runtime.root.object.define(.object(map), for: MapMenuMovieBridge.menuName)
        let calls = MenuMovieEventLog<String>()
        let names = [
            "Init", "SetNumMarkers", "CreateMarkers", "RefreshMarkers", "SetSelectedMarker"
        ]
        for name in names {
            AS2Natives.method(runtime.runtime, on: map, name: name) { _ in
                calls.append(name)
                return .undefined
            }
        }
        return (map, calls)
    }

    private static func markerData(_ map: AS2Object) -> [AS2Value] {
        guard let array = map.lookup("MarkerData")?.property.value.objectValue else { return [] }
        return array.ownPropertyNames.compactMap(Int.init).sorted().compactMap {
            array.lookup(String($0))?.property.value
        }
    }

    @Test func createWritesThreeValuesPerMarkerAndBuildsInSteps() throws {
        let runtime = try MenuMovieCallLog.emptyRuntime()
        let (map, calls) = Self.worldMap(runtime)
        let markers = (0 ..< 12).map {
            MapMovieMarker(name: "Place \($0)", iconType: 1, isUndiscovered: $0 > 5)
        }
        MapMenuMovieBridge.create(markers, runtime: runtime)
        #expect(calls.events == ["SetNumMarkers", "CreateMarkers", "CreateMarkers"])
        let data = Self.markerData(map)
        #expect(data.count == 36)
        #expect(data.prefix(3) == [.string("Place 0"), .integer(1), .boolean(false)])
    }

    @Test func refreshHidesMarkersOffScreenAndSelectsOne() throws {
        let runtime = try MenuMovieCallLog.emptyRuntime()
        let (map, calls) = Self.worldMap(runtime)
        MapMenuMovieBridge.refresh([SIMD2(0.25, 0.5), nil], selected: 0, runtime: runtime)
        #expect(calls.events == ["RefreshMarkers", "SetSelectedMarker"])
        #expect(Self.markerData(map) == [
            .boolean(true), .number(0.25), .number(0.5), .number(0),
            .boolean(false), .number(0), .number(0), .number(0)
        ])
    }

    @Test func theMovieCallsMarkerClickAndItsButtons() throws {
        let runtime = try MenuMovieCallLog.emptyRuntime()
        let events = MenuMovieEventLog<MapMovieEvent>()
        MapMenuMovieBridge.prepare(runtime: runtime) { events.append($0) }
        runtime.callHost("MarkerClick", arguments: [.number(3)])
        runtime.callHost("ToggleMapCallback", arguments: [])
        runtime.callHost("OpenJournalCallback", arguments: [])
        #expect(events.events == [.marker(3), .toggleLocalMap, .journal])
    }
}
