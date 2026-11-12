// A flying actor's package walks become flights. The dragon flight reads where the
// package sends the actor and reports back when it got there. See
// docs/engine/dragon-flight.md.

public import OpenSkyFormatsESM
public import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

extension PackageCoordinator {
    public func flightTarget(of actor: ReferenceKey) -> PackageFlightTarget? {
        movement.flightTarget(of: actor)
    }

    /// The flight reached the target, so the procedure's walk ends there. Only once.
    public func flightArrived(_ actor: ReferenceKey) {
        if movement.arrive(actor) {
            movementSettled(actor: actor, reason: .arrival)
        }
    }
}

/// The last place a flying actor's package sent it. It stays after arrival, so a
/// perched dragon stays on its perch when the package ends.
nonisolated struct PackageFlight: Equatable, Sendable {
    var target: PackageFlightTarget
    /// Where a perch target's seat is.
    var perchFeet: SIMD3<Float>?
    var arrived = false
}

extension PackageMovement {
    func flightTarget(of actor: ReferenceKey) -> PackageFlightTarget? {
        flights[actor]?.target
    }
}
