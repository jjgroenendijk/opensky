import OpenSkyFormatsESM
import OpenSkyGameData
@testable import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyWorldInterface
import Testing

struct CompassLocationTests {
    private func site(_ x: Float, name: String = "Riverwood", known: Bool) -> MapMarkerSite {
        MapMarkerSite(
            key: .plugin(name: "Skyrim.esm", objectID: UInt32(x) + 1),
            name: name,
            position: SIMD3(x, 0, 0),
            state: MapMarkerState(isVisible: known, isDiscovered: known, canTravelTo: known)
        )
    }

    @Test func aKnownMarkerShowsFurtherThanAnUnknownOne() {
        let sites = [site(15000, known: true), site(15001, known: false), site(12000, known: false)]
        let shown = MapMarkerRules.compassLocations(sites, player: .zero, settings: .vanilla)
        #expect(shown.map(\.isKnown) == [true, false])
        #expect(shown.map(\.position.x) == [15000, 12000])
    }

    @Test func aMarkerPastTheCompassDistanceOrWithoutANameIsHidden() {
        let sites = [site(20001, known: true), site(100, name: "", known: true)]
        #expect(MapMarkerRules.compassLocations(sites, player: .zero, settings: .vanilla).isEmpty)
    }

    @Test func theOpacityFadesByTheSquaredDistance() {
        let settings = MenuMapSettings.vanilla
        #expect(MapMarkerRules.compassOpacity(squaredDistance: 0, settings: settings) == 100)
        #expect(MapMarkerRules
            .compassOpacity(squaredDistance: 5000 * 5000, settings: settings) == 87.5)
        #expect(MapMarkerRules.compassOpacity(squaredDistance: 1e9, settings: settings) == 50)
    }

    @Test func theCompassDrawsALocationWithItsOpacity() {
        let place = CompassLocation(position: SIMD3(100, 0, 0), isKnown: true, opacityPercent: 60)
        let markers = HUDCore.markers(for: nil, locations: [place], cameraPosition: .zero)
        #expect(markers == [HUDCompassMarker(
            headingDegrees: 90,
            opacityPercent: 60,
            kind: .location
        )])
    }
}
