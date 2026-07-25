// Provisional playback categories for the M9.1 audio graph.
//
// The real taxonomy is deliberately deferred: milestone 9.2.1 decodes the game's
// own `SNDR`/`SDSC` records and reveals which categories vanilla content actually
// uses, at which point this list is renamed or replaced to match (issue #153,
// "Decisions settled" item 6). Keep it small and cheap to rename — nothing may
// persist these raw values or bake them into a file format.

nonisolated enum AudioCategory: String, CaseIterable, Sendable {
    case music
    case effects
    case ambience

    /// Panel label. Capitalized display form of the case name.
    var displayName: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }

    /// Accessibility-identifier fragment (`Audio<Category>VolumeControl`).
    var identifierFragment: String {
        displayName
    }
}
