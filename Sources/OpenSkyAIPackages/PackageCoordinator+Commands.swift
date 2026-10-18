// What a package's procedures ask for: walks, seats, stops, and acts the world
// answers. See docs/engine/package-schedules.md.

import OpenSkyFormatsESM
import simd

extension PackageCoordinator {
    /// Feeds one event to one running procedure. A procedure that ends moves the tree on.
    func step(_ actor: ReferenceKey, with event: PackageProcedureEvent, leaf: Int) {
        guard var execution = executions[actor], var session = session(for: actor) else {
            return
        }
        let before = execution.ends
        let commands = execution.runner.handle(event, leaf: leaf, host: &session)
        executions[actor] = execution
        apply(commands, actor: actor, endsBefore: before)
    }

    /// Senses then ticks every running procedure of the actor, in node order.
    func tick(_ actor: ReferenceKey, by delta: Float) {
        guard let execution = executions[actor], let session = session(for: actor) else {
            return
        }
        for leaf in execution.runner.runningNodes {
            let machine = executions[actor]?.runner.running[leaf]?.machine
            if
                let machine, machine.watchesTarget, let watched = machine.setup.watched,
                let senses = session.senses(watching: watched)
            {
                step(actor, with: .sensed(senses), leaf: leaf)
            }
            step(actor, with: .tick(delta), leaf: leaf)
        }
    }

    func apply(_ commands: [PackageTreeCommand], actor: ReferenceKey, endsBefore: Int) {
        reportEnds(of: actor, since: endsBefore)
        for tagged in commands {
            switch tagged.command {
            case let .move(point):
                requestMove(actor, to: point)
            case .sit:
                guard let seat = executions[actor]?.runner.running[tagged.leaf]?.setup.seat else {
                    continue
                }
                executions[actor]?.seat = seat
                world?.seatPackageActor(actor, in: seat)
            case let .act(action):
                let result = world?.packageAction(action, actor: actor) ?? .failed
                step(actor, with: .acted(result), leaf: tagged.leaf)
            case .stop:
                waitingMoves[actor] = nil
                world?.stopPackageActor(mounts[actor] ?? actor)
            case .playLoop:
                continue
            }
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
