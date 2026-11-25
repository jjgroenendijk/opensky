// What a package's procedures ask for: walks, seats, stops, and acts the world
// answers. See docs/engine/package-schedules.md.

import OpenSkyFormatsESM
import OpenSkyWorldInterface
import OpenSkyWorldState

extension PackageCoordinator {
    /// Feeds one event to one running procedure. A procedure that ends moves the tree on.
    /// A result deeper than `maxStepDepth` waits for the next tick.
    func step(_ actor: ReferenceKey, with event: PackageProcedureEvent, leaf: Int) {
        let depth = stepDepth[actor, default: 0]
        guard depth < Self.maxStepDepth else {
            heldSteps[actor, default: []].append((event, leaf))
            return
        }
        guard let before = executions[actor]?.ends, var session = session(for: actor) else {
            return
        }
        stepDepth[actor] = depth + 1
        defer { stepDepth[actor] = depth == 0 ? nil : depth }
        // In place: a copy taken out and written back copies the whole tree state.
        let commands = executions[actor]?.runner.handle(event, leaf: leaf, host: &session) ?? []
        apply(commands, actor: actor, endsBefore: before)
    }

    /// True when the actor's package failed on a walk that gave up, and the wait before
    /// the package starts again has passed. The tree is dropped, so the next pass over
    /// the schedule starts it anew.
    func retriesFailedWalk(_ actor: ReferenceKey, by delta: Float) -> Bool {
        guard let waited = failedWalkSeconds[actor] else { return false }
        guard executions[actor]?.runner.outcome == .failed else {
            failedWalkSeconds[actor] = nil
            return false
        }
        guard waited + delta >= Self.failedWalkRetrySeconds else {
            failedWalkSeconds[actor] = waited + delta
            return false
        }
        failedWalkSeconds[actor] = nil
        leaveExecution(of: actor)
        return true
    }

    /// Senses then ticks every running procedure of the actor, in node order.
    func tick(_ actor: ReferenceKey, by delta: Float) {
        CommandSteps(host: self).tick(actor, by: delta)
    }

    func apply(_ commands: [PackageTreeCommand], actor: ReferenceKey, endsBefore: Int) {
        CommandSteps(host: self).apply(commands, actor: actor, endsBefore: endsBefore)
    }

    /// Turns an actor at its seat to the seat's heading, and seats it once the turn left
    /// is inside the furniture angle. The entry clip starts with the seating.
    func turnToSeat(_ actor: ReferenceKey, by delta: Float) {
        CommandSteps(host: self).turnToSeat(actor, by: delta)
    }

    /// A walk to a seat that gave up inside the furniture radius has arrived.
    func reachedFurniture(_ actor: ReferenceKey) -> Bool {
        CommandSteps(host: self).reachedFurniture(actor)
    }

    /// A sandboxing actor that holds an idle marker uses it as its next activity.
    func arrivesAtIdleMarker(_ actor: ReferenceKey, leaf: Int) -> Bool {
        executions[actor]?.takesIdleMarkers(leaf) == true
            && world?.packageActorHoldsIdleMarker(actor) == true
    }
}

extension PackageCoordinator {
    /// Runs the package commands of one actor.
    struct CommandSteps {
        let host: PackageCoordinator

        func tick(_ actor: ReferenceKey, by delta: Float) {
            let settings = host.settings
            let world = host.world
            for held in host.heldSteps.removeValue(forKey: actor) ?? [] {
                host.step(actor, with: held.event, leaf: held.leaf)
            }
            host.turnToSeat(actor, by: delta)
            guard
                !host.retriesFailedWalk(actor, by: delta), let execution = host.executions[actor],
                let session = host.session(for: actor)
            else {
                return
            }
            let hours = world?.packageClock.map { $0.totalGameSeconds / GameClock.secondsPerHour }
            for leaf in execution.runner.runningNodes {
                let machine = host.executions[actor]?.runner.running[leaf]?.machine
                if
                    let machine, machine.watchesTarget, let watched = machine.setup.watched,
                    var senses = session.senses(watching: watched)
                {
                    if machine.follows {
                        senses.fellows = host.fellowFollowers(of: watched, excluding: actor)
                        senses.followerSpacing = settings.follow.spaceBetweenFollowers
                    }
                    host.step(actor, with: .sensed(senses), leaf: leaf)
                }
                if
                    let machine, let feet = world?.packageActorPosition(actor),
                    machine.hasReachedArea(feet)
                {
                    host.step(actor, with: .arrived, leaf: leaf)
                }
                if machine?.isSandbox == true, let hours {
                    host.step(actor, with: .clock(hours: hours), leaf: leaf)
                }
                // The idle runtime can give a marker after the walk ended.
                if
                    host.executions[actor]?.runner.running[leaf]?.machine.isWandering == true,
                    host.arrivesAtIdleMarker(actor, leaf: leaf)
                {
                    host.step(actor, with: .arrivedAtIdleMarker, leaf: leaf)
                }
                host.step(actor, with: .tick(delta), leaf: leaf)
            }
        }

        func apply(_ commands: [PackageTreeCommand], actor: ReferenceKey, endsBefore: Int) {
            let movement = host.movement
            let world = host.world
            host.reportEnds(of: actor, since: endsBefore)
            for tagged in commands {
                switch tagged.command {
                case let .move(point):
                    // The idle runtime walks a sandboxing actor to its marker, so the
                    // sandbox's own walk counts as done.
                    if host.arrivesAtIdleMarker(actor, leaf: tagged.leaf) {
                        host.step(actor, with: .arrivedAtIdleMarker, leaf: tagged.leaf)
                    } else {
                        host.requestMove(actor, to: point)
                    }
                case .sit:
                    guard let seat = host.executions[actor]?.seat(of: tagged.leaf) else { continue }
                    host.executions[actor]?.seat = seat
                    host.seatTurns[actor] = FurnitureSeatTurn(seat: seat)
                    host.turnToSeat(actor, by: 0)
                case let .act(action):
                    let result = world?.packageAction(action, actor: actor) ?? .failed
                    host.step(actor, with: .acted(result), leaf: tagged.leaf)
                case .stop:
                    movement.waiting[actor] = nil
                    world?.stopPackageActor(host.mounts[actor] ?? actor)
                case let .pace(gait):
                    movement.paces[actor] = gait
                case .playLoop:
                    continue
                case let .endActivity(activity):
                    if PackageProcedureMachine.isSeatActivity(activity) {
                        host.seatTurns[actor] = nil
                        let seat = host.executions[actor]?.seat
                        host.executions[actor]?.seat = nil
                        world?.unseatPackageActor(actor, from: seat)
                    }
                    world?.packageSandboxActivityEnded(activity, actor: actor)
                case let .seekSeat(request):
                    let seat = world?.packageSandboxSeat(for: actor, in: request)
                    host.step(actor, with: .seatOffered(seat), leaf: tagged.leaf)
                }
            }
        }

        func turnToSeat(_ actor: ReferenceKey, by delta: Float) {
            let settings = host.settings
            let world = host.world
            guard var turn = host.seatTurns[actor] else { return }
            turn.seconds += delta
            let arrival = settings.furnitureArrival
            let remaining = world?.turnPackageActor(
                actor, toHeading: turn.seat.seat.heading, within: arrival.angleToleranceRadians
            )
            guard
                FurnitureArrival.mayEnter(
                    remainingTurn: remaining, seconds: turn.seconds, settings: arrival
                )
            else {
                host.seatTurns[actor] = turn
                return
            }
            host.seatTurns[actor] = nil
            world?.seatPackageActor(actor, in: turn.seat)
        }

        func reachedFurniture(_ actor: ReferenceKey) -> Bool {
            let settings = host.settings
            let world = host.world
            guard
                let execution = host.executions[actor], let leaf = execution.runner.mover,
                let seat = execution.seat(of: leaf), let feet = world?.packageActorPosition(actor)
            else { return false }
            return FurnitureArrival.hasArrived(
                feet: feet, seat: seat.seat,
                askedRadius: execution.runner.running[leaf]?.setup.setup.radius ?? 0,
                settings: settings.furnitureArrival
            )
        }
    }
}
