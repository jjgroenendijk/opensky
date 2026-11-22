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
    var listed: Set<ReferenceKey> = []
    /// Where an actor placed into an interior cell stands, by cell.
    var entrances: [FormID: SIMD3<Float>]?

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

    /// An actor the roster does not list, such as a guard placed as a temporary reference.
    public func offscreenArrival(_ actor: ReferenceKey) -> OffscreenActor? {
        guard
            actor != .player, !isListed(actor),
            game.worldState.component(ActorDeathState.self, for: actor)?.isDead != true,
            let plugin = home(of: actor)
        else { return nil }
        return OffscreenRoster.actor(
            actor, plugin: plugin, delta: game.worldState.delta(for: actor)
        )
    }

    private func isListed(_ actor: ReferenceKey) -> Bool {
        _ = roster()
        return cache.listed.contains(actor)
    }

    /// A reference where it stands now, or the actor's editor place. An "in cell" location
    /// is the editor place in the actor's own cell, else the entrance of an interior cell.
    public func offscreenPlace(
        of location: Package.Location, actor: OffscreenActor
    ) -> OffscreenPlace? {
        let radius = Float(max(0, location.radius))
        switch location.kind {
        case .nearReference:
            return location.formID.flatMap { place(ofFormID: $0, radius: radius) }
        case .nearLinkedReference:
            let links = home(of: actor.key)?.entry.placedActor?.details.linkedReferences ?? []
            let keyword = FormID(location.value).nonNull
            return links.first { $0.keyword == keyword }
                .flatMap { place(ofFormID: $0.ref, radius: radius) }
        case .nearEditorLocation:
            return home(of: actor.key).map { OffscreenRoster.editorPlace(of: $0, radius: radius) }
        case .inCell:
            guard let cell = location.formID else { return nil }
            if let home = home(of: actor.key), home.home == .interior(cell) {
                return OffscreenRoster.editorPlace(of: home, radius: radius)
            }
            // Anywhere in the cell counts as being there.
            return entrance(of: cell).map {
                OffscreenPlace(
                    location: .interior(cell), worldspace: nil, point: $0,
                    radius: .greatestFiniteMagnitude
                )
            }
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
        cache.listed = Set(roster)
        return roster
    }

    private func entrance(of cell: FormID) -> SIMD3<Float>? {
        if let entrances = cache.entrances {
            return entrances[cell]
        }
        guard
            let store = game.aiRecords?.locationStore, let lookup = game.streamer.placedRecords
        else { return nil }
        let entrances = OffscreenRoster.entrances(
            placements: store.persistentPlacements,
            interiorCell: { lookup.interiorCell(holding: $0) }
        )
        cache.entrances = entrances
        return entrances[cell]
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
            let key = ReferenceKey.resolve(formID, using: resolver), key != .player,
            let placement = bridge.placement(of: key),
            let location = placement.location
        else { return nil }
        return OffscreenPlace(
            location: location, worldspace: placement.worldspace,
            point: placement.state.transform.position, radius: radius
        )
    }
}
