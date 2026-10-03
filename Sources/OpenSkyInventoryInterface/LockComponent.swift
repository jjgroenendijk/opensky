// Lock state of one door or container: the XLOC baseline with a runtime delta on
// top. The difficulty bands and their names are on docs/engine/locks.md.

import OpenSkyFormatsESM
import OpenSkyWorldState

/// The five pickable bands plus "requires key". `iLockLevelMaxVeryEasy` (1) bounds
/// Novice; the other bounds are the XLOC values UESP lists for REFR.
nonisolated public enum LockDifficulty: Int, CaseIterable, Comparable, Sendable {
    case novice = 1
    case apprentice
    case adept
    case expert
    case master
    case requiresKey

    /// The band a lock level falls in. Level 0 reads as Novice, as UESP notes.
    public init(level: UInt8, noviceMaximum: UInt8 = 1) {
        self = switch level {
        case 0 ... noviceMaximum: .novice
        case 0 ... 25: .apprentice
        case 0 ... 50: .adept
        case 0 ... 75: .expert
        case 0 ... 100: .master
        default: .requiresKey
        }
    }

    public var isPickable: Bool {
        self != .requiresKey
    }

    /// English names. The install's `sLockLevelName*` settings are lstrings.
    public var name: String {
        switch self {
        case .novice: "Novice"
        case .apprentice: "Apprentice"
        case .adept: "Adept"
        case .expert: "Expert"
        case .master: "Master"
        case .requiresKey: "Requires Key"
        }
    }

    /// The GMST suffix: `fSweetSpotVeryEasy` is Novice, `...VeryHard` is Master.
    public var settingSuffix: String {
        switch self {
        case .novice: "VeryEasy"
        case .apprentice: "Easy"
        case .adept: "Average"
        case .expert: "Hard"
        case .master: "VeryHard"
        case .requiresKey: "Impossible"
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

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

    public var difficulty: LockDifficulty {
        LockDifficulty(level: level)
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
