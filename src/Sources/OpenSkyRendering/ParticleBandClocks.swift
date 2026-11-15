// Far particle systems step less often, in the shared update bands. A skipped frame's
// time goes into the next step. See docs/engine/update-bands.md.

import OpenSkyGameData
import simd

/// The band clock of each live particle system.
nonisolated struct ParticleBandClocks {
    static let bands = UpdateBands.standard
    /// A long step makes a fast particle jump, so no system waits longer than this.
    static let longestStep = UpdateBand.reduced.interval

    private var clocks: [ObjectIdentifier: UpdateBandClock] = [:]

    /// Drops the clocks of systems that left the scene.
    mutating func keep(_ systems: [AnyObject]) {
        guard clocks.count > systems.count else { return }
        let live = Set(systems.map(ObjectIdentifier.init))
        clocks = clocks.filter { live.contains($0.key) }
    }

    /// The seconds `system`, placed at `position`, steps by this frame, or nil when its
    /// band skips the frame.
    mutating func step(
        of system: AnyObject, at position: SIMD3<Float>, viewer: SIMD3<Float>, deltaTime: Float
    ) -> Float? {
        let key = ObjectIdentifier(system)
        var clock = clocks[key] ?? UpdateBandClock(phase: Self.phase(of: position))
        let band = Self.bands.band(atDistance: simd_distance(viewer, position))
        let step = clock.tick(deltaTime, band: band, longest: Self.longestStep)
        clocks[key] = clock
        return step
    }

    /// The band each system stepped in last, for `openskycli game state frame`.
    var bandCounts: [UpdateBand: Int] {
        clocks.values.reduce(into: [:]) { $0[$1.band, default: 0] += 1 }
    }

    /// From the placed position, which is the same on every run.
    private static func phase(of position: SIMD3<Float>) -> Float {
        let bits = UInt64(position.x.bitPattern) << 32 | UInt64(position.y.bitPattern)
        return UpdateBandClock.phase(of: bits ^ UInt64(position.z.bitPattern))
    }
}
