// Far observers are built again less often, in the shared update bands, measured from
// the nearest target. See docs/engine/update-bands.md.

public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyPerceptionInterface
import simd

/// The kept candidates and their band clocks.
nonisolated struct PerceptionBandedRoster {
    static let bands = UpdateBands.standard

    var candidates: [ReferenceKey: PerceptionCandidate] = [:]
    var clocks: [ReferenceKey: UpdateBandClock] = [:]
    /// Seconds since the last roster refresh.
    var waited: Float = 0
    /// The targets the last refresh read, for the runtime's target read right after it.
    var targets: [PerceptionTarget]?

    mutating func takeTargets() -> [PerceptionTarget]? {
        defer { targets = nil }
        return targets
    }

    /// True when the candidate of `key` at `feet` must be built again this refresh.
    mutating func isDue(_ key: ReferenceKey, feet: SIMD3<Float>, viewers: [SIMD3<Float>]) -> Bool {
        let distance = viewers.map { simd_distance($0, feet) }.min() ?? 0
        var clock = clocks[key] ?? UpdateBandClock(phase: UpdateBandClock.phase(of: key))
        let due = clock.tick(waited, band: Self.bands.band(atDistance: distance)) != nil
        clocks[key] = clock
        return due || candidates[key] == nil
    }

    /// Keeps the fresh candidates, drops the departed ones, and lists the roster in the
    /// order the session gave it.
    mutating func apply(_ refresh: (present: [ReferenceKey], fresh: [PerceptionCandidate]))
        -> [PerceptionCandidate]
    {
        for candidate in refresh.fresh {
            candidates[candidate.observer.key] = candidate
        }
        if candidates.count != refresh.present.count {
            let present = Set(refresh.present)
            candidates = candidates.filter { present.contains($0.key) }
            clocks = clocks.filter { present.contains($0.key) }
        }
        waited = 0
        return refresh.present.compactMap { candidates[$0] }
    }
}

extension PerceptionCoordinator {
    /// The band `observer` is built again in, or nil when it is not on the roster.
    public func perceptionBand(of observer: ReferenceKey) -> UpdateBand? {
        bandedRoster.clocks[observer]?.band
    }

    func bandedCandidates() -> [PerceptionCandidate] {
        let targets = world.perceptionTargets()
        bandedRoster.targets = targets
        let viewers = targets.map(\.feet)
        let refresh = world.perceptionCandidates { key, feet in
            bandedRoster.isDue(key, feet: feet, viewers: viewers)
        }
        return bandedRoster.apply(refresh)
    }
}
