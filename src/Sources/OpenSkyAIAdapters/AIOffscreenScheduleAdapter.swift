// The session side of the off-screen schedule: which persistent actors it runs, where a
// package place is while its cell is not loaded, and the move itself. The rules are in
// `OffscreenRoster`.

import OpenSkyActorsInterface
public import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWorldInterface
import OpenSkyWorldState

/// Each actor's plugin record and home, read once per session: a pass reads them all.
@MainActor
public final class OffscreenHomeCache {
    var homes: [ReferenceKey: PluginPlacement?] = [:]
    /// Every persistent placed actor of the load order, in key order.
    var roster: [ReferenceKey]?

    public init() {}
}

/// Part of `AIWorldAdapter`, over the package state host.
public struct AIOffscreenScheduleAdapter {
    let game: any AIPackageStateHost
    let cache: OffscreenHomeCache

    /// Every persistent placed actor, without the player, the dead, and the disabled. The
    /// game keeps each of them at a process level, whether its base is placed once or often.
    public func offscreenActors() -> [OffscreenActor] {
        roster().compactMap { key in
            guard
                game.worldState.component(ActorDeathState.self, for: key)?.isDead != true,
                let plugin = home(of: key)
            else { return nil }
            return OffscreenRoster.actor(
                key,
                plugin: plugin,
                delta: game.worldState.delta(for: key)
            )
        }
    }

    /// A reference where it stands now, or the actor's editor place. An "in cell" location
    /// is found only when it is the actor's own editor cell.
    public func offscreenPlace(
        of location: Package.Location, actor: OffscreenActor
    ) -> OffscreenPlace? {
        let radius = Float(max(0, location.radius))
        switch location.kind {
        case .nearReference:
            return location.formID.flatMap { place(ofFormID: $0, radius: radius) }
        case .nearEditorLocation:
            return home(of: actor.key).map { OffscreenRoster.editorPlace(of: $0, radius: radius) }
        case .inCell:
            guard
                let cell = location.formID,
                let home = home(of: actor.key), home.home == .interior(cell)
            else { return nil }
            return OffscreenRoster.editorPlace(of: home, radius: radius)
        default:
            return nil
        }
    }

    public func isLoaded(_ place: OffscreenPlace) -> Bool {
        OffscreenRoster.isLoaded(
            place, resident: game.streamer.residentCellLocations,
            worldspace: game.streamer.residentWorldspace
        )
    }

    public func loadedExit(from cell: FormID) -> OffscreenPlace? {
        guard let lookup = game.streamer.placedRecords else { return nil }
        let streamer = game.streamer
        return OffscreenRoster.exit(from: cell, through: OffscreenRoster.Doors(
            entries: residentTeleportDoors(),
            interiorCell: { lookup.interiorCell(holding: $0) },
            arrival: { lookup.arrival(through: $0) },
            location: { streamer.cellLocation(of: $0) },
            worldspace: streamer.residentWorldspace
        ))
    }

    /// The loaded doors that lead somewhere, by FormID. Each scene lists its doors, so no
    /// pass copies every resident reference.
    private func residentTeleportDoors() -> [RuntimeReferenceEntry] {
        let streamer = game.streamer
        let scenes = streamer.interiorScene.map { [$0] } ?? Array(streamer.composition.cells.values)
        return scenes.flatMap { scene in
            scene.doors.compactMap { door in
                door.destination == nil ? nil : scene.references.entry(for: door.reference)
            }
        }.sorted { $0.formID.rawValue < $1.formID.rawValue }
    }

    /// Writes the place into the cell that will draw the actor, so no other cell rebuilds.
    public func placeOffscreenActor(_ actor: ReferenceKey, at place: OffscreenPlace) {
        guard let bridge = game.scripts.bridge else { return }
        let scale = bridge.placement(of: actor)?.state.transform.scale ?? 1
        game.worldState.set(
            ReferenceTransformOverride(position: place.point, scale: scale),
            for: actor, in: place.location
        )
        bridge.relocate(actor, to: place.location, worldspace: place.worldspace)
    }

    private func roster() -> [ReferenceKey] {
        if let roster = cache.roster {
            return roster
        }
        guard let store = game.aiRecords?.locationStore else { return [] }
        let roster = OffscreenRoster.keys(
            placements: store.persistentPlacements, unique: store.uniqueActorReferences
        )
        cache.roster = roster
        return roster
    }

    private func home(of key: ReferenceKey) -> PluginPlacement? {
        if let cached = cache.homes[key] {
            return cached
        }
        let plugin = game.streamer.pluginPlacement(of: key)
        cache.homes[key] = plugin
        return plugin
    }

    private func place(ofFormID formID: FormID, radius: Float) -> OffscreenPlace? {
        guard
            let bridge = game.scripts.bridge,
            let resolver = bridge.formIDResolver,
            let key = ReferenceKey.resolve(formID, using: resolver),
            let placement = bridge.placement(of: key),
            let location = placement.location
        else { return nil }
        return OffscreenPlace(
            location: location, worldspace: placement.worldspace,
            point: placement.state.transform.position, radius: radius
        )
    }
}
