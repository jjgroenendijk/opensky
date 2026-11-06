// Where the reference game's player stands beyond the cell: the location and the map
// marker the bridge moved them to. See docs/tools/reference-sky-music.md.

/// The player's location. The game keeps no editor IDs for locations, so `editorID` is
/// often empty; the keywords name its type, such as `LocTypeTown`.
nonisolated public struct ReferenceLocation: Codable, Equatable, Sendable {
    public var editorID: String
    public var formID: UInt32
    public var keywords: [String]
    public var parent: String
    /// Nil from a bridge built before it reported clearing.
    public var cleared: Bool?
}

/// The map marker the last `marker <name>` line moved the player to.
nonisolated public struct ReferenceMarker: Codable, Equatable, Sendable {
    public var found: Bool
    public var formID: UInt32
    /// The `TNAM` marker type, such as 2 for a town.
    public var type: Int
    public var flags: Int
}
