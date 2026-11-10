// Where the reference game's player stands beyond the cell: the location and the map
// marker the bridge moved them to. See docs/tools/reference-sky-music.md.

/// The player's location. The game keeps no editor IDs for locations, so `editorID` is
/// often empty; the keywords name its type, such as `LocTypeTown`.
nonisolated struct ReferenceLocation: Codable, Equatable, Sendable {
    var editorID: String
    var formID: UInt32
    var keywords: [String]
    var parent: String
    /// Nil from a bridge built before it reported clearing.
    var cleared: Bool?
}

/// The map marker the last `marker <name>` line moved the player to.
nonisolated struct ReferenceMarker: Codable, Equatable, Sendable {
    var found: Bool
    var formID: UInt32
    /// The `TNAM` marker type, such as 2 for a town.
    var type: Int
    var flags: Int
}
