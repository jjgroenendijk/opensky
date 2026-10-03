// Which shipped scripts are traps: every script named `trap*`, plus the triggers
// and hazards the trap scripts extend or link to. See docs/engine/traps.md.

nonisolated public enum TrapScriptFamily {
    public static let members: Set = [
        "pressureplate", "pressurereleaseplate", "tripwire", "darttrap", "bladetrap",
        "bladetraphit", "macetrap", "swingingwalltrap", "hazard", "hazardbase",
        "magicplacehazard", "defaultbipressureplate"
    ]

    public static func contains(_ scriptName: String) -> Bool {
        let lowered = scriptName.lowercased()
        return lowered.hasPrefix("trap") || members.contains(lowered)
    }
}
