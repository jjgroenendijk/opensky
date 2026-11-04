// What scripts and quest aliases change in an actor's `ACBS` record flags. A script's
// `SetGhost`, `SetEssential`, or `SetProtected` wins over the record; a quest alias with
// the Essential or Protected flag adds it while its quest runs (UESP "Skyrim Mod:Mod File
// Format/QUST"). See docs/engine/papyrus-script-state.md.

import OpenSkyFormatsESM

nonisolated public struct ActorFlagOverrides: Equatable, Sendable {
    /// Flags a script turned on.
    public var set: ActorBase.Flags = []
    /// Flags a script turned off, which hides the record's flag.
    public var cleared: ActorBase.Flags = []
    /// Flags a filled alias of a running quest gives.
    public var fromAliases: ActorBase.Flags = []

    public init(
        set: ActorBase.Flags = [], cleared: ActorBase.Flags = [],
        fromAliases: ActorBase.Flags = []
    ) {
        self.set = set
        self.cleared = cleared
        self.fromAliases = fromAliases
    }

    /// One script choice: true sets the flag, false clears it, nil leaves the record.
    public mutating func script(_ flag: ActorBase.Flags, _ value: Bool?) {
        guard let value else { return }
        if value {
            set.formUnion(flag)
        } else {
            cleared.formUnion(flag)
        }
    }

    public func applied(to record: ActorBase.Flags) -> ActorBase.Flags {
        record.subtracting(cleared).union(set).union(fromAliases)
    }
}
