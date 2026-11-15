// Far movers step less often, in the shared update bands, with longer walk steps.
// See docs/engine/update-bands.md.

public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyPlayer
import simd

extension NPCMovementRuntime {
    /// The band `actor` walks in, or nil when it is not walking.
    public func movementBand(of actor: ReferenceKey) -> UpdateBand? {
        guard isWalking(actor) else { return nil }
        return moverClocks.band(of: actor)
    }
}

/// When each walking mover's banded step is due, and how long its walk steps are.
struct NPCMoverClocks {
    static let bands = UpdateBands.standard
    /// The walk caps a frame at `PhysicsStep.maximumFrameTime`, so a banded step must
    /// stay under it or the walk would lose time.
    static let longestBandStep = UpdateBand.reduced.interval

    private var clocks: [ReferenceKey: UpdateBandClock] = [:]

    func band(of actor: ReferenceKey) -> UpdateBand {
        clocks[actor]?.band ?? .full
    }

    mutating func remove(_ actor: ReferenceKey) {
        clocks[actor] = nil
    }

    /// Seconds of one walk step in `band`: the physics step near the camera, longer
    /// further out, where a coarser collision sweep cannot be seen.
    static func walkStepTime(in band: UpdateBand) -> Float {
        switch band {
        case .full: PhysicsStep.fixedTimeStep
        case .near: 1.0 / 60
        case .reduced, .distant: 1.0 / 30
        }
    }

    /// The seconds `mover` steps by this frame, or nil when its band skips the frame.
    mutating func step(
        of key: ReferenceKey, mover: inout NPCMover, frameTime: Float, viewer: SIMD3<Float>?
    ) -> Float? {
        let distance = viewer.map { simd_distance($0, mover.controller.feetPosition) } ?? 0
        let band = Self.bands.band(atDistance: distance)
        var clock = clocks[key] ?? UpdateBandClock(phase: UpdateBandClock.phase(of: key))
        let step = clock.tick(frameTime, band: band, longest: Self.longestBandStep)
        clocks[key] = clock
        mover.controller.stepTime = Self.walkStepTime(in: band)
        return step
    }
}
