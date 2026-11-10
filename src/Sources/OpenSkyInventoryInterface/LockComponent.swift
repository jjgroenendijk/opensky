// Lock state of one door or container: the XLOC baseline with a runtime delta on
// top. The difficulty bands and their names are on docs/engine/locks.md.

public import OpenSkyFormatsESM
public import OpenSkyWorldState

/// A runtime override of a reference's lock: Papyrus `Lock`, a key, or a picked lock.
nonisolated public struct ReferenceLockState: WorldStateComponent, Hashable, Sendable {
    public var isLocked: Bool
    /// The XLOC level byte, 255 for "requires key".
    public var level: UInt8
    public var key: FormID?

    public static var componentKind: WorldStateComponentKind {
        .lock
    }

    public init(isLocked: Bool, level: UInt8, key: FormID?) {
        self.isLocked = isLocked
        self.level = level
        self.key = key
    }

    /// The plugin baseline, or nil when the reference has no XLOC.
    public init?(baseline lock: LockData?) {
        guard let lock else { return nil }
        self.init(isLocked: true, level: lock.level.rawValue, key: lock.key)
    }

    var difficulty: LockDifficulty {
        LockDifficulty(level: level)
    }

    public func difficulty(noviceMaximum: UInt8) -> LockDifficulty {
        LockDifficulty(level: level, noviceMaximum: noviceMaximum)
    }

    /// `delta` over `baseline`. Nil when neither exists: the reference has no lock.
    public static func resolve(
        baseline: LockData?,
        delta: ReferenceLockState?
    ) -> ReferenceLockState? {
        delta ?? ReferenceLockState(baseline: baseline)
    }
}

nonisolated extension WorldStateComponentKind {
    /// Lock state, apart from activation bookkeeping, so a relock leaves counts alone.
    public static let lock = Self(rawValue: "lock", order: 21)
}
