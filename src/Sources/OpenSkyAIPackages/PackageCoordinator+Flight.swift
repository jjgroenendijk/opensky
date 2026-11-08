// A flying actor's package walks become flights. The dragon flight reads where the
// package sends the actor and reports back when it got there. See
// docs/engine/dragon-flight.md.

public import OpenSkyFormatsESM
public import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// The last place a flying actor's package sent it. It stays after arrival, so a
/// perched dragon stays on its perch when the package ends.
nonisolated struct PackageFlight: Equatable, Sendable {
    var target: PackageFlightTarget
    /// Where a perch target's seat is.
    var perchFeet: SIMD3<Float>?
    var arrived = false
}

extension PackageCoordinator {
    public func flightTarget(of actor: ReferenceKey) -> PackageFlightTarget? {
        flights[actor]?.target
    }

    /// The flight reached the target, so the procedure's walk ends there. Only once.
    public func flightArrived(_ actor: ReferenceKey) {
        guard flights[actor]?.arrived == false else { return }
        flights[actor]?.arrived = true
        movementSettled(actor: actor, reason: .arrival)
    }

    /// Flat distance from a perch within which a walk ends on the perch itself.
    static let perchReach: Float = 1536

    /// A sit procedure flies to its seat's furniture; any other walk to its point. A
    /// perched dragon whose next walk ends by its perch, as a shout from the tower,
    /// stays perched and has arrived at once.
    func requestFlight(_ actor: ReferenceKey, to point: SIMD3<Float>) {
        let seat = executions[actor]?.runner.running.values.lazy.compactMap(\.setup.seat).first
        if
            seat == nil, let current = flights[actor], current.arrived,
            let perch = current.perchFeet,
            simd_length(SIMD2(point.x - perch.x, point.y - perch.y)) < Self.perchReach
        {
            movementSettled(actor: actor, reason: .arrival)
            return
        }
        flights[actor] = PackageFlight(
            target: seat.map { .perch($0.furniture) } ?? .point(point),
            perchFeet: seat?.seat.root
        )
    }
}
