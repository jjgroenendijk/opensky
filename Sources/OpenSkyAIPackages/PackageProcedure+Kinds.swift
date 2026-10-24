// How each procedure kind starts, what it does on arrival, and how a follower reacts
// to where its target stands. Behaviour from the Creation Kit wiki procedure pages.

import OpenSkyFormatsESM
import OpenSkyPhysics
import OpenSkyWorldInterface
import simd

nonisolated extension PackageProcedureMachine {
    /// What a kind does when its walk ends.
    enum Arrival: Equatable {
        case complete
        case nextPoint
        case loop(PackageLoopClip)
        case sit
        case idle(Float)
        /// Stay at the place until another package or a timer moves it on.
        case hold
        /// Do the kind's act at the place.
        case act
        /// Stand near the target until it moves away again.
        case follow
        /// Start the next sandbox activity.
        case sandbox
    }

    private static let arrivals: [PackageProcedureKind: Arrival] = [
        .travel: .complete, .hover: .complete, .useIdleMarker: .complete,
        .followTo: .complete, .escort: .complete, .flee: .complete,
        .patrol: .nextPoint, .orbit: .nextPoint,
        .sleep: .sit, .eat: .loop(.eat), .sit: .sit,
        .wander: .idle(wanderIdleSeconds), .sandbox: .sandbox,
        .holdPosition: .hold, .guardArea: .hold, .flightGrab: .hold, .wait: .hold,
        .keepAnEyeOn: .hold,
        .activate: .act, .acquire: .act, .dialogueActivate: .act, .useWeapon: .act,
        .useMagic: .act, .shout: .act, .forceGreet: .act, .say: .act,
        .follow: .follow
    ]

    /// Kinds that act at once, without a walk first.
    private static let actsInPlace: Set<PackageProcedureKind> = [
        .lockDoors, .unlockDoors, .find, .say
    ]

    /// Kinds that watch their target and move when it does.
    private static let watchers: Set<PackageProcedureKind> = [
        .follow, .followTo, .escort, .flee, .forceGreet, .keepAnEyeOn, .guardArea
    ]

    public var watchesTarget: Bool {
        Self.watchers.contains(kind) && setup.watched != nil
    }

    public mutating func start() -> [PackageProcedureCommand] {
        guard state == .ready || isSearching else { return [] }
        if case .unsupported = kind {
            state = .failed
            return []
        }
        if Self.actsInPlace.contains(kind), let action = arrivalAction() {
            return act(action)
        }
        return startMoving()
    }

    private var isSearching: Bool {
        if case .searching = state {
            return true
        }
        return false
    }

    private mutating func startMoving() -> [PackageProcedureCommand] {
        switch kind {
        case .wander:
            return move(to: nextWanderPoint())
        case .sandbox:
            return startSandbox()
        case .wait, .keepAnEyeOn:
            state = .waiting
            timer = kind == .wait && setup.seconds > 0 ? setup.seconds : nil
            return []
        case .follow, .forceGreet:
            // A follower or greeter waits for its first sense, which says where the target is.
            state = .waiting
            return []
        case .flee where setup.flag:
            state = .waiting
            return []
        default:
            guard setup.walks else {
                state = .moving
                return handleArrival()
            }
            return move(to: goal)
        }
    }

    /// Where the walk of a walking kind goes: its target, else its place.
    private var goal: SIMD3<Float> {
        destination ?? center
    }

    mutating func handleArrival() -> [PackageProcedureCommand] {
        switch Self.arrivals[kind] ?? .complete {
        case .complete:
            state = .complete
            return []
        case .nextPoint:
            return nextPatrolPoint()
        case let .loop(clip):
            state = .looping(clip)
            return [.playLoop(clip)]
        case .sit:
            state = .seated
            return [.sit]
        case let .idle(seconds):
            state = .idleStop(secondsRemaining: seconds)
            return []
        case .hold, .follow:
            state = .waiting
            return []
        case .sandbox:
            return beginSandboxActivity(.wandering)
        case .act:
            guard let action = arrivalAction() else {
                state = .failed
                return []
            }
            return act(action)
        }
    }

    private mutating func nextPatrolPoint() -> [PackageProcedureCommand] {
        guard pathIndex < path.count else {
            // A one-point patrol has nowhere to go back from, so it ends.
            if repeats, !path.isEmpty, let first = destination {
                pathIndex = 0
                laps += 1
                return [.move(to: first)]
            }
            state = .complete
            return []
        }
        pathIndex += 1
        return [.move(to: path[pathIndex - 1])]
    }

    /// The act a kind does at its place, or nil when it lacks the target it needs.
    private func arrivalAction() -> PackageAction? {
        let target = setup.targets.indices.contains(targetIndex) ? setup.targets[targetIndex] : nil
        switch kind {
        case .lockDoors, .unlockDoors:
            return .setDoorsLocked(kind == .lockDoors, center: center, radius: radius)
        case .find:
            return setup.selector.map { .find($0, center: center, radius: radius) }
        case .activate:
            return target.map(PackageAction.activate)
        case .acquire:
            return target.map(PackageAction.pickUp)
        case .dialogueActivate:
            return target.map { .talk(to: $0) }
        case .say:
            return .say(topic: setup.topic, to: target ?? setup.watched)
        case .forceGreet:
            return .forceGreet(topic: setup.topic)
        default:
            return combatAction(target: target)
        }
    }

    private func combatAction(target: ReferenceKey?) -> PackageAction? {
        switch kind {
        case .useWeapon: .attack(target, startsCombat: setup.startsCombat)
        case .useMagic: .cast(setup.selector, at: target)
        case .shout: .shout(setup.selector, at: target)
        default: nil
        }
    }

    mutating func handleSenses(_ senses: PackageSenses) -> [PackageProcedureCommand] {
        guard let target = senses.watched else { return [] }
        let distance = simd_distance(senses.actor, target)
        switch kind {
        case .follow, .followTo:
            let goal = FollowSettings.spacedGoal(
                target, fellows: senses.fellows, spacing: senses.followerSpacing
            )
            return follow(goal, distance: distance, targetGait: senses.watchedGait)
        case .escort:
            return escort(distance: distance)
        case .flee where setup.flag:
            return flee(from: target, actor: senses.actor, distance: distance)
        case .forceGreet:
            return greet(target, distance: distance)
        case .guardArea:
            return guardArea(intruder: target)
        default:
            return []
        }
    }

    /// Walks to the target, kept apart from the other followers, when it is farther than
    /// the maximum radius, and walks again once it moved on or changed gait. It sneaks
    /// while the target sneaks, and sprints while the target sprints or is far ahead.
    private mutating func follow(
        _ target: SIMD3<Float>, distance: Float, targetGait: LocomotionGait?
    ) -> [PackageProcedureCommand] {
        guard state == .waiting || state == .moving else { return [] }
        let gait = Self.followGait(distance: distance, targetGait: targetGait)
        let moved = lastGoal.map { simd_distance($0, target) > Self.followSlack } ?? true
        let repaced = state == .moving && gait != pace
        guard distance > max(setup.far, setup.near), moved || repaced else { return [] }
        pace = gait
        return [.pace(gait)] + move(to: target)
    }

    static func followGait(distance: Float, targetGait: LocomotionGait?) -> LocomotionGait? {
        switch targetGait {
        case .sneak: .sneak
        case .sprint: .sprint
        default: distance > followSprintDistance ? .sprint : nil
        }
    }

    /// The escort stops while its charge is farther than the follow distance.
    private mutating func escort(distance: Float) -> [PackageProcedureCommand] {
        let limit = max(setup.far, Self.followSlack)
        if state == .moving, distance > limit {
            state = .waiting
            return [.stop]
        }
        if state == .waiting, distance <= limit {
            return move(to: goal)
        }
        return []
    }

    /// Runs straight away from the threat and is done once it is `far` away.
    private mutating func flee(
        from threat: SIMD3<Float>, actor: SIMD3<Float>, distance: Float
    ) -> [PackageProcedureCommand] {
        let safe = max(setup.far, Self.followSlack)
        guard distance < safe else {
            state = .complete
            return [.stop]
        }
        guard state == .waiting else { return [] }
        var away = actor - threat
        away.z = 0
        let direction = simd_length(away) > 0 ? simd_normalize(away) : SIMD3(1, 0, 0)
        return move(to: actor + direction * safe)
    }

    /// Waits until the player is in the trigger place, then walks up and greets.
    private mutating func greet(
        _ player: SIMD3<Float>,
        distance: Float
    ) -> [PackageProcedureCommand] {
        guard state == .waiting || state == .moving else { return [] }
        if distance <= Self.greetDistance {
            return act(.forceGreet(topic: setup.topic))
        }
        let inTrigger = radius <= 0 || simd_distance(player, center) <= radius
        guard inTrigger else { return [] }
        let moved = lastGoal.map { simd_distance($0, player) > Self.followSlack } ?? true
        return moved ? move(to: player) : []
    }
}
