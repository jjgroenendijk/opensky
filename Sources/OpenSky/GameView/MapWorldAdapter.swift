// App side of `MapMenuCoordinator`: the Tamriel markers from the session data,
// their saved states, the view, quest targets, and the fast travel trip.

import Foundation
import OpenSkyCombat
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMenus
import OpenSkyPhysics
import OpenSkyProgression
import OpenSkyQuests
import OpenSkyQuestsInterface
import OpenSkyRendering
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

final class MapWorldAdapter {
    unowned let game: GameViewController
    /// Marker names and places are fixed for a session, so they resolve once.
    private var baseSites: [MapMarkerSite]?
    private var strings: LocalizedStrings?

    init(game: GameViewController) {
        self.game = game
    }

    var records: MenuRecordData? {
        (game.worldData as? MenuDataProviding)?.menuRecords
    }

    func text(_ value: LString?) -> String? {
        if strings == nil {
            strings = game.localizedStringsLoader?()
        }
        return strings?.resolve(value)
    }

    private func sites() -> [MapMarkerSite] {
        if let baseSites {
            return baseSites
        }
        guard let records, let tamriel = records.tamriel else { return [] }
        let world = ResolvedFormID(plugin: "Skyrim.esm", objectID: tamriel.formID.rawValue)
        let sites = records.markers.markers(in: world).map { entry in
            MapMarkerSite(
                key: ReferenceKey(resolved: entry.reference),
                name: text(entry.name) ?? "\(entry.reference.objectID)",
                position: entry.position,
                state: MapMarkerState(record: entry.marker)
            )
        }
        baseSites = sites
        return sites
    }
}

extension MapWorldAdapter: MapMenuWorld {
    var menuInputConsumer: (any MenuInputConsumer)? {
        game
    }

    var playerPosition: SIMD3<Float>? {
        game.renderer?.locomotion.status.feetPosition
    }

    var playerCell: CellSceneLocation? {
        game.streamer?.currentCellLocation
    }

    func mapMarkerSites() -> [MapMarkerSite] {
        sites().map { site in
            var site = site
            if let state = game.worldState.component(MapMarkerState.self, for: site.key) {
                site.state = state
            }
            return site
        }
    }

    func storeMarkerState(_ state: MapMarkerState, for key: ReferenceKey) {
        game.worldState.set(state, for: key)
    }

    var mapSettings: MenuMapSettings {
        records?.mapSettings ?? .vanilla
    }

    var worldMapLimits: WorldMapLimits? {
        guard game.streamer?.interiorScene == nil, let map = records?.tamriel?.details.map else {
            return nil
        }
        return WorldMapLimits(map: map)
    }

    func setMapView(eye: SIMD3<Float>, lookAt: SIMD3<Float>) {
        game.renderer?.setCinematicCamera(CinematicCameraPose(eye: eye, lookAt: lookAt))
    }

    func clearMapView() {
        game.renderer?.setCinematicCamera(nil)
    }

    var localMapFog: LocalMapFogState {
        get { game.worldState.component(LocalMapFogState.self, for: .player) ?? LocalMapFogState() }
        set { game.worldState.set(newValue, for: .player) }
    }

    func showNotification(_ text: String) {
        game.hud.showNotification(text)
    }

    func awardExperience(_ amount: Int) {
        _ = game.progression.awardCharacterExperience(Float(amount))
    }

    var fastTravelContext: FastTravelContext {
        var context = FastTravelContext()
        context.hostilesNear = game.combat.combatLoopSnapshot.hostileCount > 0
        context.inAir = !(game.renderer?.walkController.isGrounded ?? true)
        return context
    }

    /// The trip takes game time for the walk, then lands at the marker.
    func travel(to marker: MapMarkerSite) -> Bool {
        guard let renderer = game.renderer, let streamer = game.streamer else { return false }
        let from = renderer.locomotion.status.feetPosition
        let walk = (game.worldData as? MovementConfigurationProviding)?
            .movementConfiguration.walkSpeed.value ?? 80
        let seconds = FastTravelRule.gameSeconds(
            distance: simd_distance(from, marker.position), walkSpeed: walk, speedMultiplier: 1,
            timeScale: GameClock.defaultTimescale
        )
        renderer
            .gameClock = GameClock(totalGameSeconds: renderer.gameClock.totalGameSeconds + seconds)
        let rotation = SIMD3<Float>(0, 0, renderer.freeFlyCamera.yaw)
        let camera = SceneCamera.teleport(placement: .init(
            position: marker.position,
            rotation: rotation
        ))
        if streamer.interiorScene != nil {
            streamer.leaveInterior(camera: camera)
        } else {
            renderer.camera = camera
            renderer.reseedMovement(camera: camera)
        }
        game.saveGames.autosave(.travel)
        return true
    }

    func refusalText(_ refusal: FastTravelRefusal) -> String {
        text(records?.menuTexts[refusal.rawValue]) ?? refusal.rawValue
    }

    /// Displayed, unfinished objectives of the quest the journal has selected.
    var questTargets: [QuestTargetMarker] {
        guard let entry = game.journal.selectedEntry(), let runtime = game.journal.runtime else {
            return []
        }
        let requests = entry.quest.objectives.flatMap { objective in
            let state = entry.state.objectives.first { $0.index == objective.index }
            guard let state, state.isDisplayed, !state.isCompleted else {
                return [QuestTargetRequest]()
            }
            return objective.targets.map {
                QuestTargetRequest(
                    quest: entry.quest.formID,
                    text: text(objective.displayText) ?? "Objective \(objective.index)",
                    aliasID: $0.aliasID, conditionsPass: true
                )
            }
        }
        return QuestTargetResolver.resolve(
            requests,
            alias: { quest, alias in
                runtime.aliasReference(alias: UInt32(bitPattern: alias), in: quest)
            },
            place: { [weak game] key in
                game?.streamer?.referenceEntry(key: key)?.placedReference.map {
                    .placed(position: $0.placement.position, cell: nil)
                }
            }
        )
    }
}
