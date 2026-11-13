// App side of `MapMenuCoordinator`: the Tamriel markers from the session data,
// their saved states, the view, quest targets, and the fast travel trip.

import Foundation
import OpenSkyActorsInterface
import OpenSkyCamera
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyCrimeInterface
public import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
public import OpenSkyMenus
public import OpenSkyMenusInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyQuestsInterface
import OpenSkyRendering
import OpenSkyRuntimeState
public import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldConditions
public import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `MapWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
public protocol MapWorldHost: MenuInputConsumer, SendableMetatype {
    var audio: any AudioPort { get }
    var hud: any HUDPort { get }
    var messages: any MessageCoordinatorPort { get }
    var localizedStringsLoader: (() -> LocalizedStrings)? { get }
    var gameSession: (any GameSessionPort)? { get }
    var streamer: any CellStreamerPort { get }
    var menuRecords: (any MenuRecordsPort)? { get }
    var mountWorld: any MountWorldPort { get }
    var worldState: any WorldStateStorePort { get }
}

/// Every host a `MapWorldAdapter` part reads, all one object.
public typealias MapWorldHosts = MapQuestsHost & MapRecordsHost & MapTravelHost & MapWorldHost

public final class MapWorldAdapter {
    public let game: any MapWorldHost
    let sites: MapSiteReads
    /// The map camera, so the map movie can place markers where the view sees them.
    public private(set) var mapViewPose: CinematicCameraPose?

    let hosts: any MapWorldHosts

    var mapRecords: MapRecordsAdapter {
        MapRecordsAdapter(game: hosts)
    }

    public var records: MenuRecordData? {
        mapRecords.records
    }

    public var mapWorldspace: Worldspace? {
        mapRecords.mapWorldspace
    }

    public var mapSettings: MenuMapSettings {
        mapRecords.mapSettings
    }

    public var travel: MapTravelAdapter {
        MapTravelAdapter(game: hosts, mapRecords: mapRecords)
    }

    public var quests: MapQuestsAdapter {
        MapQuestsAdapter(game: hosts)
    }

    public init(game: some MapWorldHosts) {
        hosts = game
        self.game = game
        sites = MapSiteReads(hosts: game)
    }

    /// `DESC` text lives in the `.dlstrings` table, names in `.strings`.
    public func text(_ value: LString?, kind: StringTable.Kind = .strings) -> String? {
        sites.text(value, kind: kind)
    }

    /// A plugin that overrides a string setting brings its own string table.
    public func text(_ setting: ResolvedGameText) -> String? {
        sites.text(setting)
    }

    /// One feature's string settings, or its fallbacks before the data has loaded.
    public func settingTexts<Key: GameSettingTextKey>(_: Key.Type = Key
        .self) -> GameSettingTexts<Key>
    {
        sites.settingTexts()
    }
}

extension MapWorldAdapter: MapMenuWorld {
    public var menuInputConsumer: (any MenuInputConsumer)? {
        game
    }

    public var playerPosition: SIMD3<Float>? {
        sites.playerPosition
    }

    public var playerCell: CellSceneLocation? {
        game.streamer.currentCellLocation
    }

    public func mapMarkerSites() -> [MapMarkerSite] {
        sites.mapMarkerSites()
    }

    public var mapMarkerWorldspaces: [MapWorldspaceChoice] {
        sites.mapMarkerWorldspaces
    }

    public func mapMarkerSites(in worldspace: ResolvedFormID) -> [MapMarkerSite] {
        sites.mapMarkerSites(in: worldspace)
    }

    public func storeMarkerState(_ state: MapMarkerState, for key: ReferenceKey) {
        game.worldState.set(state, for: key)
    }

    public var worldMapLimits: WorldMapLimits? {
        sites.worldMapLimits
    }

    public func setMapView(eye: SIMD3<Float>, lookAt: SIMD3<Float>) {
        let pose = CinematicCameraPose(eye: eye, lookAt: lookAt, avoidsGeometry: false)
        mapViewPose = pose
        game.gameSession?.setCinematicCamera(pose)
    }

    public func clearMapView() {
        mapViewPose = nil
        game.gameSession?.setCinematicCamera(nil)
    }

    public var localMapFog: LocalMapFogState {
        get { game.worldState.component(LocalMapFogState.self, for: .player) ?? LocalMapFogState() }
        set { game.worldState.set(newValue, for: .player) }
    }

    public func showNotification(_ text: String) {
        game.hud.showNotification(text)
    }

    public func showWorldNotice(_ notice: WorldNotice) {
        game.messages.postWorldNotice(notice)
    }

    public func playDiscoveryMusic(markerType: UInt8) {
        game.audio.musicDirector?.playDiscoveryMusic(markerType: markerType)
    }

    public func incrementStat(_ name: String) {
        game.worldState.incrementMiscStat(name)
    }

    public func showQuestMarkers(_ positions: [SIMD3<Float>]) {
        game.hud.updateQuestTargets(positions)
    }

    public var mapWorldspaceName: String? {
        mapWorldspace?.editorID
    }

    public var playerSetMarker: PlayerSetMapMarker? {
        get { sites.playerSetMarker }
        set { sites.playerSetMarker = newValue }
    }

    public var playerMarkerTexts: GameSettingTexts<PlayerMarkerText> {
        settingTexts()
    }

    public func ask(_ text: String, buttons: [String], answer: @escaping (Int) -> Void) {
        game.messages.presentChoices(title: nil, text: text, buttons: buttons, answer: answer)
    }

    public func showPlayerSetMarker(_ position: SIMD3<Float>?) {
        game.hud.updatePlayerSetMarker(position)
    }

    public func showCompassLocations(_ locations: [CompassLocation]) {
        game.hud.updateCompassLocations(locations)
    }

    public func refusalText(_ refusal: FastTravelRefusal) -> String {
        text(records?.menuTexts[refusal.rawValue]) ?? refusal.rawValue
    }
}

extension MapWorldAdapter: MapWorldPort {}

/// The marker sites and string texts of the map. Marker names and places are fixed for a
/// session, so they resolve once, per map worldspace.
final class MapSiteReads {
    let hosts: any MapWorldHosts
    private var baseSites: [ResolvedFormID: [MapMarkerSite]] = [:]
    private var strings: LocalizedStrings?

    init(hosts: any MapWorldHosts) {
        self.hosts = hosts
    }

    var game: any MapWorldHost {
        hosts
    }

    private var records: MenuRecordData? {
        MapRecordsAdapter(game: hosts).records
    }

    private var mapWorldspace: Worldspace? {
        MapRecordsAdapter(game: hosts).mapWorldspace
    }

    /// `DESC` text lives in the `.dlstrings` table, names in `.strings`.
    func text(_ value: LString?, kind: StringTable.Kind = .strings) -> String? {
        loadedStrings?.resolve(value, kind: kind)
    }

    /// A plugin that overrides a string setting brings its own string table.
    func text(_ setting: ResolvedGameText) -> String? {
        loadedStrings?.scoped(to: setting.sourcePlugin).resolve(setting.text)
    }

    /// One feature's string settings, or its fallbacks before the data has loaded.
    func settingTexts<Key: GameSettingTextKey>(_: Key.Type = Key
        .self) -> GameSettingTexts<Key>
    {
        game.menuRecords.map {
            GameSettingTexts<Key>.resolve(store: $0.gameSettings) { [weak self] in self?.text($0) }
        } ?? .vanilla
    }

    private var loadedStrings: LocalizedStrings? {
        if strings == nil {
            strings = game.localizedStringsLoader?()
        }
        return strings
    }

    private func sites() -> [MapMarkerSite] {
        guard
            let name = mapWorldspace?.editorID,
            let world = records?.worldspaceIDs[name]
        else { return [] }
        if let cached = baseSites[world] {
            return cached
        }
        let sites = baseSites(in: world)
        baseSites[world] = sites
        return sites
    }

    private func baseSites(in world: ResolvedFormID) -> [MapMarkerSite] {
        (records?.markers.markers(in: world) ?? []).map { entry in
            MapMarkerSite(
                key: ReferenceKey(resolved: entry.reference),
                name: text(entry.name) ?? "\(entry.reference.objectID)",
                position: entry.position,
                state: MapMarkerState(record: entry.marker),
                iconType: entry.marker.type?.rawValue ?? 0
            )
        }
    }

    private func withSavedStates(_ sites: [MapMarkerSite]) -> [MapMarkerSite] {
        sites.map { site in
            var site = site
            if let state = game.worldState.component(MapMarkerState.self, for: site.key) {
                site.state = state
            }
            return site
        }
    }

    var playerPosition: SIMD3<Float>? {
        game.gameSession?.walkController.feetPosition
    }

    func mapMarkerSites() -> [MapMarkerSite] {
        withSavedStates(sites())
    }

    var mapMarkerWorldspaces: [MapWorldspaceChoice] {
        guard let records else { return [] }
        let names = Dictionary(records.worldspaceIDs.map { ($1, $0) }) { first, _ in first }
        return records.markers.countsByWorldspace.keys.map { world in
            let name = names[world]
            return MapWorldspaceChoice(
                formID: world, name: name ?? "\(world.plugin) \(world.objectID)"
            )
        }.sorted { $0.name < $1.name }
    }

    func mapMarkerSites(in worldspace: ResolvedFormID) -> [MapMarkerSite] {
        withSavedStates(baseSites(in: worldspace))
    }

    var worldMapLimits: WorldMapLimits? {
        guard game.streamer.interiorScene == nil, let map = mapWorldspace?.details.map else {
            return nil
        }
        return WorldMapLimits(map: map)
    }

    var playerSetMarker: PlayerSetMapMarker? {
        get { game.worldState.component(PlayerSetMapMarker.self, for: .player) }
        set {
            if let newValue {
                game.worldState.set(newValue, for: .player)
            } else {
                game.worldState.reset(.playerSetMapMarker, for: .player)
            }
        }
    }
}
