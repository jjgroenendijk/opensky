// Map marker discovery, the map camera, fog, quest targets, and fast travel.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
@testable import OpenSkyMenus
import OpenSkyWorldInterface
import Testing

@MainActor
private final class FakeMapWorld: MapMenuWorld, MenuInputConsumer {
    var playerPosition: SIMD3<Float>? = SIMD3(0, 0, 0)
    var playerCell: CellSceneLocation? = .exterior(CellCoordinate(x: 0, y: 0))
    var sites: [MapMarkerSite]
    let mapSettings = MenuMapSettings.vanilla
    var worldMapLimits: WorldMapLimits? = WorldMapLimits(
        minimum: SIMD2(-100_000, -100_000), maximum: SIMD2(100_000, 100_000),
        minHeight: 50000, maxHeight: 80000, initialPitch: 50
    )
    var localMapFog = LocalMapFogState()
    var fastTravelContext = FastTravelContext()
    var questTargets: [QuestTargetMarker] = []
    var view: (eye: SIMD3<Float>, lookAt: SIMD3<Float>)?
    var notifications: [String] = []
    var experience = 0
    var travelled: [String] = []

    init(sites: [MapMarkerSite]) {
        self.sites = sites
    }

    var menuInputConsumer: (any MenuInputConsumer)? {
        self
    }

    func handleMenuInput(_ event: MenuInputEvent) {}

    func mapMarkerSites() -> [MapMarkerSite] {
        sites
    }

    var mapMarkerWorldspaces = [
        MapWorldspaceChoice(
            formID: ResolvedFormID(plugin: "Skyrim.esm", objectID: 0x3C),
            name: "Tamriel"
        )
    ]

    func mapMarkerSites(in worldspace: ResolvedFormID) -> [MapMarkerSite] {
        worldspace.objectID == 0x3C ? sites : []
    }

    func storeMarkerState(_ state: MapMarkerState, for key: ReferenceKey) {
        if let index = sites.firstIndex(where: { $0.key == key }) {
            sites[index].state = state
        }
    }

    func setMapView(eye: SIMD3<Float>, lookAt: SIMD3<Float>) {
        view = (eye, lookAt)
    }

    func clearMapView() {
        view = nil
    }

    func showNotification(_ text: String) {
        notifications.append(text)
    }

    func awardExperience(_ amount: Int) {
        experience += amount
    }

    func travel(to marker: MapMarkerSite) -> Bool {
        travelled.append(marker.name)
        return true
    }

    func refusalText(_ refusal: FastTravelRefusal) -> String {
        refusal.rawValue
    }
}

struct MapMenuCoordinatorTests {
    private static func key(_ id: UInt32) -> ReferenceKey {
        ReferenceKey(resolved: ResolvedFormID(plugin: "Skyrim.esm", objectID: id))
    }

    private static let hidden = MapMarkerState(
        isVisible: false,
        isDiscovered: false,
        canTravelTo: false
    )

    private static func site(_ id: UInt32, _ name: String, at x: Float) -> MapMarkerSite {
        MapMarkerSite(key: key(id), name: name, position: SIMD3(x, 0, 0), state: hidden)
    }

    @Test @MainActor
    func walkingCloseDiscoversOnceWithExperienceAndFog() {
        let world = FakeMapWorld(sites: [
            Self.site(1, "Riverwood", at: 900),
            Self.site(2, "Whiterun", at: 5000)
        ])
        let menu = MapMenuCoordinator(menuMode: MenuModeController())
        menu.attach(world: world)
        menu.tick()
        #expect(world.notifications == ["Discovered Riverwood"])
        #expect(world.experience == 10)
        #expect(world.sites[0].state.canTravelTo)
        #expect(!world.sites[1].state.isVisible)
        #expect(world.localMapFog.exploredCount(.exterior(CellCoordinate(x: 0, y: 0))) > 0)
        menu.tick()
        #expect(world.notifications.count == 1, "no repeat before the player moves")
    }

    @Test @MainActor
    func theInspectorRevealsDiscoversAndHidesOneMarker() {
        let world = FakeMapWorld(sites: [
            Self.site(1, "Riverwood", at: 900),
            Self.site(2, "Whiterun", at: 5000)
        ])
        let menu = MapMenuCoordinator(menuMode: MenuModeController())
        menu.attach(world: world)
        menu.inspectMarker(offset: -1)
        menu.apply(.reveal)
        #expect(world.sites[1].state == MapMarkerAction.reveal.state)
        #expect(world.sites[0].state == Self.hidden, "only the inspected marker changes")
        menu.apply(.discover)
        #expect(world.sites[1].state.canTravelTo)
        #expect(menu.snapshot
            .inspectedMarker == "Whiterun (Tamriel, 2 of 2): shown, discovered, travel")
        menu.apply(.hide)
        #expect(world.sites[1].state == Self.hidden)
        menu.inspectWorldspace(offset: 1)
        #expect(menu.snapshot.inspectedMarker?.hasPrefix("Riverwood") == true)
    }

    @Test @MainActor
    func revealAllOpensEveryMarkerAndResetFogForgetsSquares() {
        let world = FakeMapWorld(sites: [
            Self.site(1, "Riverwood", at: 900),
            Self.site(2, "Whiterun", at: 5000)
        ])
        let menu = MapMenuCoordinator(menuMode: MenuModeController())
        menu.attach(world: world)
        menu.tick()
        menu.revealAll()
        #expect(world.sites.allSatisfy { $0.state.isVisible && $0.state.canTravelTo })
        #expect(menu.snapshot.lastResult == "Markers revealed: 1")
        menu.resetFog()
        #expect(world.localMapFog.explored.isEmpty)
    }

    @Test @MainActor
    func scriptsAddMarkersWithOrWithoutTravel() {
        let world = FakeMapWorld(sites: [Self.site(1, "Bleak Falls", at: 90000)])
        let menu = MapMenuCoordinator(menuMode: MenuModeController())
        menu.attach(world: world)
        menu.addToMap(Self.key(1), allowFastTravel: false)
        #expect(menu.isVisible(Self.key(1)))
        #expect(!world.sites[0].state.canTravelTo)
        menu.addToMap(Self.key(1), allowFastTravel: true)
        #expect(world.sites[0].state.canTravelTo)
    }

    @Test @MainActor
    func worldMapOpensTheCameraAndTravelsToTheNearestMarker() {
        let world = FakeMapWorld(sites: [Self.site(1, "Riverwood", at: 900)])
        let menuMode = MenuModeController()
        let menu = MapMenuCoordinator(menuMode: menuMode)
        menu.attach(world: world)
        menu.tick()
        #expect(menu.open())
        #expect(menuMode.topMenu == MapMenuCoordinator.identifier)
        #expect((world.view?.eye.z ?? 0) >= 50000)
        #expect(menu.snapshot.selected == "Riverwood")
        menu.zoom(by: 100_000)
        #expect(menu.snapshot.cameraHeight == 50000, "zoom clamps at the minimum height")
        menu.route(.button(.accept))
        #expect(world.travelled == ["Riverwood"])
        #expect(!menu.isOpen)
        #expect(world.view == nil)
    }

    @Test @MainActor
    func refusalKeepsTheMenuOpenAndNamesTheReason() {
        let world = FakeMapWorld(sites: [Self.site(1, "Riverwood", at: 900)])
        world.fastTravelContext.inCombat = true
        let menu = MapMenuCoordinator(menuMode: MenuModeController())
        menu.attach(world: world)
        menu.tick()
        menu.open()
        menu.travelToSelected()
        #expect(menu.isOpen)
        #expect(menu.lastResult == "sNoFastTravelCombat")
        menu.fastTravelEnabled = false
        world.fastTravelContext.inCombat = false
        menu.travelToSelected()
        #expect(menu.lastResult == "sNoFastTravelScriptBlock")
    }

    @Test @MainActor
    func interiorsOpenTheLocalMap() {
        let world = FakeMapWorld(sites: [])
        world.worldMapLimits = nil
        let menu = MapMenuCoordinator(menuMode: MenuModeController())
        menu.attach(world: world)
        menu.open()
        #expect(menu.mode == .local)
        #expect(world.view?.lookAt == SIMD3(0, 0, 0))
    }

    @Test
    func questTargetsFollowHoldersAndStopAtTheDepth() {
        let request = QuestTargetRequest(
            quest: FormID(0x10), text: "Get the claw", aliasID: 3,
            conditionsPass: true
        )
        let claw = Self.key(5)
        let chest = Self.key(6)
        let markers = QuestTargetResolver.resolve(
            [request],
            alias: { _, _ in claw },
            place: { key in
                key == claw ? .heldBy(chest) : .placed(position: SIMD3(1, 2, 3), cell: nil)
            }
        )
        #expect(markers.first?.anchor == chest)
        #expect(markers.first?.position == SIMD3(1, 2, 3))
        let loop = QuestTargetResolver.resolve(
            [request], alias: { _, _ in claw }, place: { _ in .heldBy(claw) }
        )
        #expect(loop.isEmpty)
    }

    @Test
    func carryingMoreThanTheCapacityRefuses() {
        #expect(FastTravelRule.isOverencumbered(carried: 300.5, capacity: 300))
        #expect(!FastTravelRule.isOverencumbered(carried: 300, capacity: 300))
        #expect(!FastTravelRule.isOverencumbered(carried: 999, capacity: nil))
        var context = FastTravelContext()
        context.overencumbered = true
        #expect(FastTravelRule.refusal(context) == .overencumbered)
        context.alarmed = true
        #expect(FastTravelRule.refusal(context) == .alarm)
    }

    @Test
    func fastTravelTimeGrowsWithDistance() {
        let near = FastTravelRule.gameSeconds(
            distance: 1000,
            walkSpeed: 100,
            speedMultiplier: 1,
            timeScale: 20
        )
        let far = FastTravelRule.gameSeconds(
            distance: 2000,
            walkSpeed: 100,
            speedMultiplier: 1,
            timeScale: 20
        )
        #expect(near == 200)
        #expect(far == 400)
        #expect(FastTravelRule.gameSeconds(
            distance: 1,
            walkSpeed: 0,
            speedMultiplier: 1,
            timeScale: 1
        ) == 0)
    }

    @Test
    func localMapProjectsAndSplitsFog() {
        let view = LocalMapView.exterior(player: SIMD3(100, 100, 0), grid: 1)
        #expect(view.project(SIMD3(2048, 2048, 0)) == SIMD2(0.5, 0.5))
        #expect(view.project(SIMD3(9000, 0, 0)) == nil)
        let square = LocalMapFog.square(
            of: SIMD3(4095, 0, 0),
            cell: .exterior(CellCoordinate(x: 0, y: 0))
        )
        #expect(square.column == 7)
        #expect(square.row == 0)
    }
}
