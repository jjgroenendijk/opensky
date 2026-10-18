// Runs the procedure tree of each simulated actor's current package: one a scene or a
// quest alias holds, or one the actor's own schedule picked.
// See docs/engine/package-schedules.md, "Procedure tree" and "In a session".

import OpenSkyFormatsESM
import simd

/// A walk that found every mover slot taken, and its place in the queue.
nonisolated struct PackagePendingMove: Equatable, Sendable {
    let point: SIMD3<Float>
    let ticket: Int
}

extension PackageCoordinator {
    /// Starts, keeps, or drops each actor's tree, gives waiting walks a free slot, then
    /// ticks every running tree.
    func advanceTrees(by delta: Float) {
        let ridden = Set(mounts.values)
        for actor in Set(executions.keys).union(registeredActors.keys).sorted() {
            guard ridden.contains(actor) else {
                syncExecution(actor)
                continue
            }
            if executions[actor]?.fromSchedule == true {
                leaveExecution(of: actor)
            }
        }
        retryWaitingMoves()
        for actor in executions.keys.sorted() where !ridden.contains(actor) {
            tick(actor, by: delta)
        }
    }

    /// Starts the tree of the actor's current package when the package changed, and
    /// drops the tree when the actor may not run one now.
    func syncExecution(_ actor: ReferenceKey) {
        guard
            let runtime, let world, let current = runtime.currentPackage(for: actor),
            runsTree(actor, package: current.package)
        else {
            leaveExecution(of: actor)
            return
        }
        guard executions[actor]?.package != current.package.formID else {
            releaseIfEnded(actor)
            return
        }
        guard world.packageActorPosition(actor) != nil, var session = session(for: actor) else {
            return
        }
        leaveExecution(of: actor)
        let fromSchedule = runtime.hold(for: actor) == nil
        var execution = PackageOverrideExecution(package: current, fromSchedule: fromSchedule)
        updateMount(actor, rides: execution.ridesHorse)
        let commands = execution.runner.start(host: &session)
        executions[actor] = execution
        if fromSchedule, current.package.general.flags.contains(.mustComplete) {
            self.runtime?.setCompleting(current.package.formID, actor: actor)
        }
        world.packageProcedure(PackageScriptEvent(
            kind: .begin, actor: actor, package: current.package
        ))
        apply(commands, actor: actor, endsBefore: 0)
    }

    /// A scene or alias package always runs. The actor's own package waits while a
    /// conversation or arrest holds the actor, and while it fights or is dead.
    private func runsTree(_ actor: ReferenceKey, package: Package) -> Bool {
        guard let runtime, let world else { return false }
        if runtime.hold(for: actor) != nil {
            return true
        }
        guard actor != .player, !runtime.isSuspended(actor) else { return false }
        switch world.packageActorActivity(actor) {
        case .free: return true
        case .fighting: return package.general.flags.contains(.ignoreCombat)
        case .dead: return false
        }
    }

    /// An own package whose tree ended lets the schedule pick again, for its
    /// "Must Complete" and "Once Per Day" flags.
    private func releaseIfEnded(_ actor: ReferenceKey) {
        guard
            var runtime, let world, let clock = world.packageClock,
            let execution = executions[actor], execution.fromSchedule,
            execution.runner.outcome != nil,
            let package = runtime.currentPackage(for: actor)?.package,
            runtime.completing(for: actor) == package.formID
            || package.general.flags.contains(.oncePerDay)
        else { return }
        runtime.packageEnded(
            actor: actor, clock: clock, context: world.packageConditionContext(clock: clock)
        )
        self.runtime = runtime
    }

    /// Drops the actor's tree and runs the change fragment of the package it left. A
    /// schedule walk stops with it, unless a fight now moves the actor.
    func leaveExecution(of actor: ReferenceKey) {
        waitingMoves[actor] = nil
        guard let execution = executions.removeValue(forKey: actor) else { return }
        if runtime?.completing(for: actor) == execution.package {
            runtime?.setCompleting(nil, actor: actor)
        }
        if
            execution.fromSchedule, execution.runner.mover != nil,
            world?.packageActorActivity(actor) == .free
        {
            world?.stopPackageActor(mounts[actor] ?? actor)
        }
        if let seat = execution.seat {
            world?.unseatPackageActor(actor, from: seat)
        }
        if let package = try? store?.resolve(execution.package).package {
            world?.packageProcedure(
                PackageScriptEvent(kind: .change, actor: actor, package: package)
            )
        }
    }

    /// The session side of the actor's current package.
    func session(for actor: ReferenceKey) -> PackageTreeSession? {
        guard
            let runtime, let world, let clock = world.packageClock,
            let current = runtime.currentPackage(for: actor)
        else { return nil }
        let execution = executions[actor].flatMap {
            $0.package == current.package.formID ? $0 : nil
        }
        return PackageTreeSession(
            world: world, actor: actor, aliasQuest: runtime.hold(for: actor)?.aliasQuest,
            package: current,
            values: execution?.values ?? PackageOverrideExecution.values(of: current),
            clock: clock,
            translation: store?.translation(of: current.definition.formID)
        )
    }

    /// True while the actor's current package has the Ignore Combat flag.
    public func ignoresCombat(_ actor: ReferenceKey) -> Bool {
        runtime?.currentPackage(for: actor)?.package.general.flags.contains(.ignoreCombat)
            ?? false
    }

    /// Picks the actor's package again and starts its tree from the root, as the AI
    /// panel's Reevaluate asks.
    public func restart(_ actor: ReferenceKey) {
        runtime?.setSuspended(false, actor: actor)
        leaveExecution(of: actor)
        resume(actor)
    }

    /// Scene and alias walks take a free slot first, then the others in the order
    /// they asked, so no actor waits for ever.
    func retryWaitingMoves() {
        let queue = waitingMoves.sorted { lhs, rhs in
            let left = runtime?.hold(for: lhs.key) != nil
            let right = runtime?.hold(for: rhs.key) != nil
            return left == right ? lhs.value.ticket < rhs.value.ticket : left
        }
        for (actor, pending) in queue {
            requestMove(actor, to: pending.point)
        }
    }

    /// A move that finds every mover slot taken waits in the queue. The room check comes
    /// first, because a refused move would still pay for its path search.
    func requestMove(_ actor: ReferenceKey, to point: SIMD3<Float>) {
        let execution = executions[actor]
        let walker = mounts[actor] ?? actor
        let result = world.map { world in
            world.packageMoverHasRoom(for: walker)
                ? world.movePackageActor(
                    walker, to: point,
                    direct: execution?.isDirect ?? false, gait: execution?.gait
                )
                : .busy
        }
        if result == .busy {
            let ticket = waitingMoves[actor]?.ticket ?? nextMoveTicket
            nextMoveTicket = max(nextMoveTicket, ticket + 1)
            waitingMoves[actor] = PackagePendingMove(point: point, ticket: ticket)
        } else {
            waitingMoves[actor] = nil
        }
        if result == .failed || result == nil {
            movementSettled(actor: actor, reason: .giveUp)
        }
    }
}
