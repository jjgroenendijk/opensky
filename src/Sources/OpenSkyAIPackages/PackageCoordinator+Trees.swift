// Runs the procedure tree of each simulated actor's current package: one a scene or a
// quest alias holds, or one the actor's own schedule picked.
// See docs/engine/package-schedules.md, "Procedure tree" and "In a session".

import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyWorldInterface
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
            runsTree(actor, package: current)
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
        var execution = PackageOverrideExecution(
            package: current, fromSchedule: fromSchedule, speeds: settings.speeds
        )
        updateMount(actor, rides: execution.ridesHorse)
        let commands = execution.runner.start(host: &session)
        executions[actor] = execution
        if fromSchedule, runtime.mustComplete(current) {
            self.runtime?.setCompleting(current.package.formID, actor: actor)
        }
        world.reportProcedure(.begin, actor: actor, package: current.package)
        apply(commands, actor: actor, endsBefore: 0)
    }

    /// A scene or alias package runs unless a follower command holds the actor. The
    /// actor's own package also waits while a conversation or arrest holds the actor, and
    /// while it fights or is dead.
    private func runsTree(_ actor: ReferenceKey, package: ResolvedPackage) -> Bool {
        guard let runtime, let world, !commandedActors.contains(actor) else { return false }
        if runtime.hold(for: actor) != nil {
            return true
        }
        guard actor != .player, !runtime.isSuspended(actor) else { return false }
        switch world.packageActorActivity(actor) {
        case .free: return true
        case .fighting:
            return runtime.fights(actor, running: package)
        case .dead, .aiDisabled: return false
        }
    }

    /// An own package whose tree ended lets the schedule pick again, for its
    /// "Must Complete" and "Once Per Day" flags.
    private func releaseIfEnded(_ actor: ReferenceKey) {
        guard
            var runtime, let world, let clock = world.packageClock,
            let execution = executions[actor], execution.fromSchedule,
            execution.runner.outcome != nil, runtime.releasesWhenEnded(actor)
        else { return }
        runtime.packageEnded(
            actor: actor, clock: clock, context: conditionContext(clock: clock)
        )
        self.runtime = runtime
    }

    /// Drops the actor's tree and runs the change fragment of the package it left. A
    /// schedule walk stops with it, unless a fight now moves the actor.
    func leaveExecution(of actor: ReferenceKey) {
        movement.forget(actor)
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
        // A seat reserved on the walk there is freed too, though the actor never sat.
        world?.unseatPackageActor(actor, from: execution.seat)
        if let package = attempt({ try store?.resolve(execution.package).package }) {
            world?.reportProcedure(.change, actor: actor, package: package)
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
        var session = PackageTreeSession(
            world: world, actor: actor, aliasQuest: runtime.holdingQuest(for: actor),
            package: current,
            values: execution?.values ?? PackageOverrideExecution.values(of: current),
            clock: clock,
            translation: store?.translation(of: current.definition.formID),
            conditionFunctions: runtime.conditionFunctions,
            makeContext: { [weak self] in
                self?.conditionContext(clock: clock) ?? world.packageConditionContext(clock: clock)
            }
        )
        session.guardWarnings = settings.guardWarnings
        session.sandboxSettings = settings.sandbox
        return session
    }

    /// True while the actor's current package has the Ignore Combat flag, or came from
    /// its combat override list, which runs in place of combat.
    public func ignoresCombat(_ actor: ReferenceKey) -> Bool {
        runtime?.ignoresCombat(actor) ?? false
    }

    /// Picks the actor's package again and starts its tree from the root, as the AI
    /// readout's Reevaluate asks.
    func restart(_ actor: ReferenceKey) {
        runtime?.setSuspended(false, actor: actor)
        leaveExecution(of: actor)
        resume(actor)
    }

    /// Scene and alias walks take a free slot first, then the others in the order
    /// they asked, so no actor waits for ever.
    func retryWaitingMoves() {
        for (actor, point) in movement.queue(held: { runtime?.hold(for: $0) != nil }) {
            requestMove(actor, to: point)
        }
    }

    func requestMove(_ actor: ReferenceKey, to point: SIMD3<Float>) {
        movement.request(
            actor,
            to: point,
            execution: executions[actor],
            walker: mounts[actor] ?? actor
        )
    }
}
