// The music the game plays when the player discovers a map marker, picked by the marker's
// type. See docs/engine/music.md#discovery-music.

nonisolated public enum DiscoveryMusic {
    /// The `MUSC` editor ID for a marker of `TNAM` type `markerType`. Location keywords
    /// play no part: a capital's own marker types (36 to 52) play the generic music.
    public static func editorID(markerType: UInt8) -> String {
        switch markerType {
        case 1: "MUSDiscoveryCity"
        case 2: "MUSDiscoveryTown"
        // Cave, Nordic ruin, Dwemer ruin, dragon lair, and mine.
        case 4, 7, 8, 12, 15: "MUSDiscoveryDungeon"
        default: "MUSDiscoveryGeneric"
        }
    }
}
