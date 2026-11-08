// The custom map marker: placing it, the questions it asks, the compass, and the rule.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
@testable import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyWorldInterface
import Testing

struct MapMenuPlayerMarkerTests {
    private static let undiscovered = MapMarkerState(
        isVisible: true, isDiscovered: false, canTravelTo: false
    )

    private static func site(_ id: UInt32, at x: Float, discovered: Bool = false) -> MapMarkerSite {
        MapMarkerSite(
            key: ReferenceKey(resolved: ResolvedFormID(plugin: "Skyrim.esm", objectID: id)),
            name: "Site \(id)", position: SIMD3(x, 0, 100),
            state: discovered
                ? MapMarkerState(isVisible: true, isDiscovered: true, canTravelTo: true)
                : undiscovered
        )
    }

    @MainActor
    private static func openMap(_ sites: [MapMarkerSite]) -> (MapMenuCoordinator, FakeMapWorld) {
        let world = FakeMapWorld(sites: sites)
        let menu = MapMenuCoordinator(menuMode: MenuModeController(), world: world)
        menu.open(.world)
        return (menu, world)
    }

    @Test @MainActor
    func placingOnOpenGroundAsksNothing() {
        let (menu, world) = Self.openMap([Self.site(1, at: 60000, discovered: true)])
        menu.placePlayerMarker()
        #expect(world.questions.isEmpty)
        #expect(world.playerSetMarker == PlayerSetMapMarker(worldspace: "Tamriel", position: .zero))
        #expect(world.compassPlayerMarker == .zero)
        #expect(menu.lastResult == "Place Marker: 0, 0")
        #expect(menu.snapshot.playerMarker == "Custom Destination at 0, 0")
    }

    @Test @MainActor
    func theMarkerGoesWhereTheMapLooks() {
        let world = FakeMapWorld(sites: [])
        world.playerPosition = SIMD3(17404, -14834, -1294)
        let menu = MapMenuCoordinator(menuMode: MenuModeController(), world: world)
        menu.open(.world)
        menu.placePlayerMarker()
        #expect(world.playerSetMarker?.position == SIMD3(17404, -14834, 0))
    }

    @Test @MainActor
    func placingOnAnUndiscoveredLocationAsks() throws {
        let (menu, world) = Self.openMap([Self.site(1, at: 1000)])
        menu.placePlayerMarker()
        let question = try #require(world.questions.first)
        #expect(question.text == PlayerMarkerText.placeUndiscovered.fallback)
        #expect(question.buttons == ["Yes", "No"])
        #expect(world.playerSetMarker == nil)
        question.answer(0)
        #expect(world.playerSetMarker?.position == SIMD3(1000, 0, 100))
    }

    @Test @MainActor
    func travelToAnUndiscoveredLocationOffersTheMarker() throws {
        let (menu, world) = Self.openMap([Self.site(1, at: 1000)])
        menu.travelToSelected()
        #expect(world.travelled.isEmpty)
        let question = try #require(world.questions.first)
        question.answer(1)
        #expect(world.playerSetMarker == nil)
        #expect(menu.lastResult == "No")
    }

    @Test @MainActor
    func aPlacedMarkerAsksToMoveRemoveOrLeave() throws {
        let (menu, world) = Self.openMap([])
        world.playerSetMarker = PlayerSetMapMarker(
            worldspace: "Tamriel", position: SIMD3(500, 500, 0)
        )
        menu.placePlayerMarker()
        let question = try #require(world.questions.first)
        #expect(question.text == "Do you want to move your marker or remove it?")
        #expect(question.buttons == ["Move It", "Remove It", "Leave It"])
        question.answer(2)
        #expect(world.playerSetMarker?.position == SIMD3(500, 500, 0))
        menu.placePlayerMarker()
        world.questions[1].answer(0)
        #expect(world.playerSetMarker?.position == .zero)
        menu.placePlayerMarker()
        world.questions[2].answer(1)
        #expect(world.playerSetMarker == nil)
        #expect(world.compassPlayerMarker == nil)
    }

    @Test @MainActor
    func aMarkerInAnotherWorldspaceStaysHidden() {
        let (menu, world) = Self.openMap([])
        world.playerSetMarker = PlayerSetMapMarker(worldspace: "DLC2SolstheimWorld", position: .one)
        menu.refreshQuestMarkers()
        #expect(menu.playerMarker == nil)
        #expect(world.compassPlayerMarker == nil)
        menu.placePlayerMarker()
        #expect(world.questions.isEmpty)
        #expect(world.playerSetMarker?.worldspace == "Tamriel")
    }

    @Test @MainActor
    func theLocalMapPlacesNothing() {
        let world = FakeMapWorld(sites: [])
        let menu = MapMenuCoordinator(menuMode: MenuModeController(), world: world)
        menu.open(.local)
        menu.placePlayerMarker()
        #expect(world.playerSetMarker == nil)
        #expect(menu.lastResult == "The custom marker needs the world map")
    }

    @Test
    func theRuleAimsAtAMarkerOnlyNearTheCentre() {
        let near = Self.site(1, at: 400)
        #expect(
            PlayerMarkerRule.target(focus: .zero, cameraHeight: 10000, nearest: near) == .site(near)
        )
        #expect(
            PlayerMarkerRule.target(focus: .zero, cameraHeight: 4000, nearest: near)
                == .ground(.zero)
        )
        #expect(PlayerMarkerRule.step(.site(near), hasMarker: true) == .askMoveOrRemove)
        let found = Self.site(2, at: 400, discovered: true)
        #expect(PlayerMarkerRule.step(.site(found), hasMarker: false) == .place(found.position))
    }
}
