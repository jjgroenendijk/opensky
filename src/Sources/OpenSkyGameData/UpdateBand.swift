// How often per-object work runs at a distance from the viewer: every frame near,
// then less often further out. Actor graphs, movement, perception, and particles
// share these bands. See docs/engine/update-bands.md.

public import OpenSkyFormatsESM

/// One distance band. A band further out runs its work less often.
nonisolated public enum UpdateBand: Int, CaseIterable, Comparable, Sendable {
    /// Every frame.
    case full
    /// 30 times a second.
    case near
    /// 15 times a second.
    case reduced
    /// 5 times a second.
    case distant

    /// Seconds between two runs of the work; zero runs it every frame.
    public var interval: Float {
        switch self {
        case .full: 0
        case .near: 1.0 / 30
        case .reduced: 1.0 / 15
        case .distant: 1.0 / 5
        }
    }

    /// The name `openskycli game state` shows.
    public var name: String {
        switch self {
        case .full: "full"
        case .near: "near"
        case .reduced: "reduced"
        case .distant: "distant"
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The distances where the bands start, in game units from the viewer.
nonisolated public struct UpdateBands: Equatable, Sendable {
    /// The actor graph distances: full up to 1024, 30 a second up to 2048, 15 a second
    /// up to 6144, and the distant band past that.
    public static let standard = Self(
        nearDistance: 1024,
        reducedDistance: 2048,
        distantDistance: 6144
    )

    public var nearDistance: Float
    public var reducedDistance: Float
    public var distantDistance: Float

    public init(nearDistance: Float, reducedDistance: Float, distantDistance: Float) {
        self.nearDistance = max(0, nearDistance)
        self.reducedDistance = max(self.nearDistance, reducedDistance)
        self.distantDistance = max(self.reducedDistance, distantDistance)
    }

    /// The band at `distance`. A distance that is not a number, such as from a missing
    /// viewer, is the full band, so the work never stops by mistake.
    public func band(atDistance distance: Float) -> UpdateBand {
        guard distance.isFinite else { return .full }
        if distance <= nearDistance {
            return .full
        }
        if distance <= reducedDistance {
            return .near
        }
        return distance <= distantDistance ? .reduced : .distant
    }
}

/// When one object's banded work is due. Time a skipped frame does not use is added to
/// the next run, so the work covers the same game time as when it runs every frame.
nonisolated public struct UpdateBandClock: Equatable, Sendable {
    public private(set) var band: UpdateBand = .full
    /// Real seconds since the last run.
    private var waited: Float = 0
    /// A share of the first interval to wait less, so objects that start together do not
    /// all run in the same frame.
    private var phase: Float

    /// `phase` in 0 ..< 1, such as `UpdateBandClock.phase(of:)` of the object's key.
    public init(phase: Float) {
        self.phase = phase.isFinite ? min(max(phase, 0), 1) : 0
    }

    /// Adds `deltaTime` in `band`. Returns the seconds the work should step by when it
    /// is due this frame, or nil when it waits. `longest` caps the interval, for work
    /// that must not take large steps.
    public mutating func tick(
        _ deltaTime: Float, band: UpdateBand, longest: Float = .infinity
    ) -> Float? {
        self.band = band
        waited += max(deltaTime, 0)
        let interval = min(band.interval, longest)
        guard waited + phase * interval >= interval else { return nil }
        let step = waited
        waited = 0
        phase = 0
        return step
    }

    /// A phase from a number that stays the same between runs, such as a FormID.
    public static func phase(of value: UInt64) -> Float {
        // Fibonacci hashing spreads close numbers, such as neighbouring FormIDs, apart.
        let mixed = value &* 0x9E37_79B9_7F4A_7C15
        return Float(mixed >> 40) / Float(1 << 24)
    }

    public static func phase(of key: ReferenceKey) -> Float {
        switch key {
        case let .plugin(_, objectID): phase(of: UInt64(objectID))
        case let .generated(sequence): phase(of: sequence)
        }
    }
}
