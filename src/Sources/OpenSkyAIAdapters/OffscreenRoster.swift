// The pure reads behind the off-screen schedule's adapter: where an actor stands, whether a
// place is loaded, and which loaded door leads out of a house.

public import OpenSkyAIPackages
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyWorldInterface
public import OpenSkyWorldState

nonisolated public enum OffscreenRoster {
    /// The persistent placed actors and the actors the location records name, in key
    /// order, without the player.
    public static func keys(
        placements: [PersistentPlacement], unique: [ReferenceKey: ReferenceKey]
    ) -> [ReferenceKey] {
        let placed = placements.compactMap { $0.actorBase == nil ? nil : $0.key }
        return Set(placed).union(unique.values).subtracting([.player]).sorted()
    }

    /// The actor where its deltas put it, or nil when it is not an enabled actor.
    public static func actor(
        _ key: ReferenceKey, plugin: PluginPlacement, delta: ReferenceStateDelta?
    ) -> OffscreenActor? {
        guard let base = plugin.entry.placedActor?.base else { return nil }
        let state = ReferenceState(baseline: plugin.entry).applying(delta)
        guard state.enableState.isEnabled else { return nil }
        let moved = delta?.component(ReferenceRelocation.self)
        let place = OffscreenPlace(
            location: moved?.location ?? plugin.home,
            worldspace: moved.map(\.worldspace) ?? plugin.worldspace,
            point: state.transform.position
        )
        return OffscreenActor(key: key, base: base, place: place)
    }

    /// Where the editor placed the reference.
    public static func editorPlace(of plugin: PluginPlacement, radius: Float) -> OffscreenPlace {
        OffscreenPlace(
            location: plugin.home, worldspace: plugin.worldspace,
            point: ReferenceState(baseline: plugin.entry).transform.position, radius: radius
        )
    }

    /// An interior is loaded when it is resident; an exterior cell also needs the resident
    /// worldspace to be its own.
    public static func isLoaded(
        _ place: OffscreenPlace, resident: Set<CellSceneLocation>, worldspace: String?
    ) -> Bool {
        guard resident.contains(place.location) else { return false }
        guard case .exterior = place.location else { return true }
        return worldspace != nil && worldspace?.lowercased() == place.worldspace?.lowercased()
    }

    /// The resident doors and how to read them, for `exit(from:through:)`.
    public struct Doors {
        public let entries: [RuntimeReferenceEntry]
        /// The interior CELL that holds a record, nil for an exterior one.
        public let interiorCell: (FormID) -> FormID?
        /// Where the other side of a door puts someone who goes through it.
        public let arrival: (PlacedReference) -> PlacedReference.Placement?
        public let location: (ReferenceKey) -> CellSceneLocation?
        public let worldspace: String?

        public init(
            entries: [RuntimeReferenceEntry],
            interiorCell: @escaping (FormID) -> FormID?,
            arrival: @escaping (PlacedReference) -> PlacedReference.Placement?,
            location: @escaping (ReferenceKey) -> CellSceneLocation?,
            worldspace: String?
        ) {
            self.entries = entries
            self.interiorCell = interiorCell
            self.arrival = arrival
            self.location = location
            self.worldspace = worldspace
        }
    }

    /// The arrival in front of the first resident door whose other side is in `cell`.
    public static func exit(from cell: FormID, through doors: Doors) -> OffscreenPlace? {
        for entry in doors.entries {
            guard
                let door = entry.placedReference,
                let inside = door.teleportDestination?.door,
                doors.interiorCell(inside) == cell,
                let arrival = doors.arrival(door),
                let location = doors.location(entry.key)
            else { continue }
            let worldspace: String? = if case .exterior = location {
                doors.worldspace
            } else {
                nil
            }
            return OffscreenPlace(
                location: location,
                worldspace: worldspace,
                point: arrival.position
            )
        }
        return nil
    }
}
