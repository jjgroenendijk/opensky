// The world map and local map: marker discovery as the player walks, the map
// camera, quest targets, the local map fog, and fast travel. The rules live in
// `MapMarkerRules`, `WorldMapCamera`, and `FastTravelRule`. See
// docs/engine/world-map.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldInterface
import simd

/// What the map reads from and does to the running game.
public protocol MapMenuWorld: AnyObject {
    var menuInputConsumer: (any MenuInputConsumer)? { get }
    var playerPosition: SIMD3<Float>? { get }
    var playerCell: CellSceneLocation? { get }
    /// The current worldspace's markers, with their saved states.
    func mapMarkerSites() -> [MapMarkerSite]
    func storeMarkerState(_ state: MapMarkerState, for key: ReferenceKey)
    var mapSettings: MenuMapSettings { get }
    /// Nil inside an interior or without map data.
    var worldMapLimits: WorldMapLimits? { get }
    /// Points the view from `eye` at `lookAt`; nil gives the view back.
    func setMapView(eye: SIMD3<Float>, lookAt: SIMD3<Float>)
    func clearMapView()
    var localMapFog: LocalMapFogState { get set }
    func showNotification(_ text: String)
    func awardExperience(_ amount: Int)
    var fastTravelContext: FastTravelContext { get }
    /// Moves the player to the marker and the clock forward. False when it could not.
    func travel(to marker: MapMarkerSite) -> Bool
    func refusalText(_ refusal: FastTravelRefusal) -> String
    var questTargets: [QuestTargetMarker] { get }
}

public enum MapMenuMode: String, Sendable {
    case world, local
}

public final class MapMenuCoordinator {
    public static let identifier: MenuIdentifier = "MapMenu"
    /// The player must move this far before discovery runs again.
    static let discoveryStep: Float = 128
    /// Exterior local maps show the loaded 5 by 5 cells.
    static let localGrid = 5

    public private(set) var mode: MapMenuMode?
    public private(set) var camera: WorldMapCamera?
    public private(set) var selected: MapMarkerSite?
    /// `Game.EnableFastTravel`; scripts turn it off during some quests.
    public var fastTravelEnabled = true
    public private(set) var lastResult: String?
    public private(set) var discoveredCount = 0
    private var lastDiscoveryPosition: SIMD3<Float>?
    private let menuMode: MenuModeController
    private weak var world: (any MapMenuWorld)?

    public init(menuMode: MenuModeController) {
        self.menuMode = menuMode
    }

    public func attach(world: any MapMenuWorld) {
        self.world = world
    }

    public var isOpen: Bool {
        mode != nil
    }

    // MARK: - Walking

    /// Discovers markers near the player and clears fog under them.
    public func tick() {
        guard mode == nil, let world, let player = world.playerPosition else { return }
        if let last = lastDiscoveryPosition, simd_distance(last, player) < Self.discoveryStep {
            return
        }
        lastDiscoveryPosition = player
        var sites = world.mapMarkerSites()
        let settings = world.mapSettings
        for change in MapMarkerRules.discover(&sites, player: player, settings: settings) {
            guard
                case let .discovered(key, name) = change,
                let site = sites.first(where: { $0.key == key })
            else { continue }
            world.storeMarkerState(site.state, for: key)
            world.showNotification("Discovered \(name)")
            world.awardExperience(settings.discoveryExperience)
            discoveredCount += 1
        }
        exploreFog(at: player)
    }

    private func exploreFog(at player: SIMD3<Float>) {
        guard let world, let cell = world.playerCell else { return }
        let square = LocalMapFog.square(of: player, cell: cell)
        var fog = world.localMapFog
        if fog.explore(cell, column: square.column, row: square.row) {
            world.localMapFog = fog
        }
    }

    // MARK: - Scripts

    public func addToMap(_ key: ReferenceKey, allowFastTravel: Bool) {
        guard let world, let site = world.mapMarkerSites().first(where: { $0.key == key }) else {
            return
        }
        world.storeMarkerState(
            MapMarkerRules.addToMap(site.state, allowFastTravel: allowFastTravel), for: key
        )
    }

    /// Shows, discovers, and opens travel to every marker, for testing travel.
    public func revealAll() {
        guard let world else { return }
        let open = MapMarkerState(isVisible: true, isDiscovered: true, canTravelTo: true)
        let sites = world.mapMarkerSites().filter {
            !($0.state.isVisible && $0.state.isDiscovered && $0.state.canTravelTo)
        }
        for site in sites {
            world.storeMarkerState(open, for: site.key)
        }
        lastResult = "Markers revealed: \(sites.count)"
    }

    /// Forgets every explored square, so the local map shows fog again.
    public func resetFog() {
        world?.localMapFog = LocalMapFogState()
        lastResult = "Fog reset"
    }

    public func isVisible(_ key: ReferenceKey) -> Bool {
        world?.mapMarkerSites().first { $0.key == key }?.state.isVisible ?? false
    }

    // MARK: - Menu

    /// The world map needs map data; inside an interior it opens the local map.
    @discardableResult
    public func open(_ requested: MapMenuMode = .world) -> Bool {
        guard mode == nil, let world, let player = world.playerPosition else { return false }
        if requested == .world, let limits = world.worldMapLimits {
            camera = WorldMapCamera(limits: limits, focus: SIMD2(player.x, player.y))
            mode = .world
        } else {
            camera = nil
            mode = .local
        }
        menuMode.inputConsumer = world.menuInputConsumer
        menuMode.present(Self.identifier)
        refreshSelection()
        applyView()
        return true
    }

    public func close() {
        guard mode != nil else { return }
        mode = nil
        camera = nil
        selected = nil
        menuMode.dismiss(Self.identifier)
        world?.clearMapView()
    }

    public func route(_ event: MenuInputEvent) {
        guard mode != nil else { return }
        switch event {
        case let .move(direction): pan(direction)
        case .button(.accept): travelToSelected()
        case .button(.cancel): close()
        case let .pointer(deltaX, deltaY): panBy(SIMD2(deltaX, -deltaY) * 0.002)
        case .release: return
        }
    }

    public func zoom(by amount: Float) {
        camera?.zoom(by: amount)
        refreshSelection()
        applyView()
    }

    public func tilt(by degrees: Float) {
        camera?.tilt(by: degrees)
        applyView()
    }

    private func pan(_ direction: MenuInputEvent.Direction) {
        let step: SIMD2<Float> = switch direction {
        case .up: SIMD2(0, 1)
        case .down: SIMD2(0, -1)
        case .left: SIMD2(-1, 0)
        case .right: SIMD2(1, 0)
        }
        panBy(step * 0.1)
    }

    /// `fraction` of the view height, so a pan feels the same at every zoom.
    private func panBy(_ fraction: SIMD2<Float>) {
        guard var camera else { return }
        camera.pan(by: fraction * camera.limits.maxHeight)
        self.camera = camera
        refreshSelection()
        applyView()
    }

    /// The marker nearest the map center, like the vanilla cursor.
    private func refreshSelection() {
        guard let world else { return }
        let center = camera.map { SIMD3($0.focus.x, $0.focus.y, 0) }
            ?? world.playerPosition ?? .zero
        let flat = { (site: MapMarkerSite) in SIMD3(site.position.x, site.position.y, 0) }
        selected = MapMarkerRules.shown(world.mapMarkerSites(), around: center).min {
            simd_distance_squared(flat($0), center) < simd_distance_squared(flat($1), center)
        }
    }

    private func applyView() {
        guard let world else { return }
        if let camera {
            world.setMapView(eye: camera.eye, lookAt: SIMD3(camera.focus.x, camera.focus.y, 0))
        } else if let player = world.playerPosition {
            let height = Float(Self.localGrid) * LocalMapView.cellSize
            world.setMapView(eye: player + SIMD3(0, -1, height), lookAt: player)
        }
    }

    public func travelToSelected() {
        guard let world, let target = selected else { return }
        var context = world.fastTravelContext
        context.enabledByScripts = fastTravelEnabled && context.enabledByScripts
        context.destinationCanTravelTo = target.state.canTravelTo
        if let refusal = FastTravelRule.refusal(context) {
            lastResult = world.refusalText(refusal)
            world.showNotification(lastResult ?? "")
            return
        }
        close()
        lastResult = world.travel(to: target) ? "Travelled to \(target.name)" : "Travel failed"
    }

    /// Selects a marker by reference, for `Game.FastTravel`.
    @discardableResult
    public func select(key: ReferenceKey) -> Bool {
        guard let site = world?.mapMarkerSites().first(where: { $0.key == key }) else {
            return false
        }
        selected = site
        return true
    }

    public var snapshot: MapMenuSnapshot {
        let sites = world?.mapMarkerSites() ?? []
        return MapMenuSnapshot(
            mode: mode?.rawValue,
            markerCount: sites.count,
            visibleCount: sites.count { $0.state.isVisible },
            discoveredCount: sites.count { $0.state.isDiscovered },
            selected: selected?.name,
            cameraHeight: camera?.height,
            cameraPitch: camera?.pitch,
            questTargets: world?.questTargets.map(\.text) ?? [],
            fastTravelEnabled: fastTravelEnabled,
            lastResult: lastResult
        )
    }
}
