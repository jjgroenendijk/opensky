// What a package's procedure asks for: walks, and seats in furniture.
// See docs/engine/package-schedules.md.

import OpenSkyFormatsESM
import simd

extension PackageCoordinator {
    func apply(_ commands: [PackageProcedureCommand], actor: ReferenceKey) {
        for command in commands {
            if command == .sit, let seat = executions[actor]?.seat {
                world?.seatPackageActor(actor, in: seat)
            }
            guard case let .move(point) = command else { continue }
            requestMove(actor, to: point)
        }
    }

    /// A move that finds every mover slot taken waits, and is asked again each tick.
    func requestMove(_ actor: ReferenceKey, to point: SIMD3<Float>) {
        let execution = executions[actor]
        let result = world?.movePackageActor(
            mounts[actor] ?? actor, to: point,
            direct: execution?.isDirect ?? false, gait: execution?.gait
        )
        waitingMoves[actor] = result == .busy ? point : nil
        if result == .failed || result == nil {
            movementSettled(actor: actor, reason: .giveUp)
        }
    }
}
