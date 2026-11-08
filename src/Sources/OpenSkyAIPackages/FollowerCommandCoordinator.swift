// Follower command mode as a state machine: a follower in the favour state waits for
// the player to pick a target, says its Favors tab line, then walks there and acts.
// `FollowerCommandRules` decides; the app answers `FollowerCommandWorld`.
// See docs/engine/follower-commands.md.

public import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyWorldInterface
import simd

/// What the command coordinator needs from the app.
@MainActor
public protocol FollowerCommandWorld: AnyObject {
    func followerCommandPosition(of actor: ReferenceKey) -> SIMD3<Float>?
    var followerCommandPlayerPosition: SIMD3<Float>? { get }
    /// The `Morality` actor value.
    func followerMorality(_ follower: ReferenceKey) -> Float
    func sayFavorLine(_ subtype: FourCC, follower: ReferenceKey)
    /// Clears the follower's doing-favour flag, saying its Exit line when `announces`.
    func endFavor(_ follower: ReferenceKey, announces: Bool)
    func moveFollower(_ follower: ReferenceKey, to point: SIMD3<Float>) -> Bool
    func stopFollower(_ follower: ReferenceKey)
    /// Stops every package of the follower until `releaseFollower`.
    func holdFollower(_ follower: ReferenceKey)
    func releaseFollower(_ follower: ReferenceKey)
    var followerCommandSettings: FollowerCommandSettings { get }
    /// True when the act took place.
    func performFollowerTask(_ task: FollowerCommandTask, follower: ReferenceKey) -> Bool
}

public final class FollowerCommandCoordinator {
    public private(set) weak var world: (any FollowerCommandWorld)?
    public let settings: FollowerCommandSettings
    public private(set) var phase = FollowerCommandPhase.idle
    public private(set) var lastDecision: FollowerCommandDecision?
    public private(set) var lastOutcome: FollowerCommandOutcome?
    /// A use-key press on a follower that is not yet a tap or a hold.
    public private(set) var pressedFollower: (follower: ReferenceKey, held: Float)?

    public init(world: any FollowerCommandWorld) {
        self.world = world
        settings = world.followerCommandSettings
    }

    public var isChoosing: Bool {
        if case .choosing = phase {
            true
        } else {
            false
        }
    }

    /// The follower entered the favour state, as `SetDoingFavor` does.
    public func favorStarted(_ follower: ReferenceKey) {
        if !isChoosing, let previous = phase.follower {
            // The same follower keeps the flag that was just set.
            if previous == follower {
                release(previous)
                lastOutcome = .cancelled
            } else {
                finish(.cancelled)
            }
        }
        phase = .choosing(follower: follower)
        lastDecision = nil
    }

    /// A script cleared the favour state, and said the Exit line itself.
    public func favorEnded(_ follower: ReferenceKey) {
        guard phase.follower == follower else { return }
        release(follower)
        phase = .idle
        lastOutcome = .cancelled
    }

    /// The use key went down on a follower. A tap or a hold decides what it does.
    public func useKeyDown(on follower: ReferenceKey) {
        pressedFollower = (follower, 0)
    }

    /// Advances the pending press. Nil while it is undecided, or with no press.
    public func advanceUseKey(by delta: Float, isDown: Bool) -> FollowerUseKey? {
        guard let pressed = pressedFollower else { return nil }
        let held = pressed.held + max(delta, 0)
        if held >= settings.holdSeconds {
            pressedFollower = nil
            return .hold(pressed.follower)
        }
        guard isDown else {
            pressedFollower = nil
            return .tap(pressed.follower)
        }
        pressedFollower = (pressed.follower, held)
        return nil
    }

    /// The player leaves command mode. True when command mode was on.
    @discardableResult
    public func cancel() -> Bool {
        guard case let .choosing(follower) = phase else { return false }
        end(follower, .cancelled)
        return true
    }

    /// The player picked `target`, or nothing. Nil outside command mode.
    @discardableResult
    public func command(_ target: FollowerCommandTarget?) -> FollowerCommandDecision? {
        guard case let .choosing(follower) = phase, let world else { return nil }
        let decision = FollowerCommandRules.decide(
            target, follower: follower, morality: world.followerMorality(follower)
        )
        lastDecision = decision
        world.sayFavorLine(decision.line, follower: follower)
        guard case let .agree(task) = decision else { return decision }
        hold(follower)
        phase = .walking(follower: follower, task: task)
        guard task.walks, !isInReach(follower, of: task) else {
            act()
            return decision
        }
        let start = world.followerCommandPosition(of: follower)
        let goal = task.action == .moveTo
            ? task.target.position : approach(to: task.target.position, from: start)
        if !world.moveFollower(follower, to: goal) {
            finish(.unreachable)
        }
        return decision
    }

    public func tick(_ delta: Float) {
        guard let world, let follower = phase.follower else { return }
        guard let position = world.followerCommandPosition(of: follower) else {
            finish(.lost)
            return
        }
        switch phase {
        case .choosing:
            let far = world.followerCommandPlayerPosition.map {
                simd_distance($0, position) > settings.radius
            } ?? false
            if far {
                end(follower, .tooFar)
            }
        case let .walking(_, task):
            if isInReach(follower, of: task) {
                act()
            }
        case let .waiting(_, left):
            if left - delta <= 0 {
                finish(.done)
            } else {
                phase = .waiting(follower: follower, left: left - delta)
            }
        case .idle:
            break
        }
    }

    /// A walk the coordinator asked for ended.
    public func movementSettled(actor: ReferenceKey, reason: NPCMovementSettleReason) {
        guard case let .walking(follower, _) = phase, follower == actor else { return }
        switch reason {
        case .arrival: act()
        case .giveUp: finish(.unreachable)
        default: break
        }
    }

    private func act() {
        guard case let .walking(follower, task) = phase, let world else { return }
        world.stopFollower(follower)
        guard task.action != .moveTo else {
            phase = .waiting(follower: follower, left: settings.waitSeconds)
            return
        }
        finish(world.performFollowerTask(task, follower: follower) ? .done : .failed)
    }

    /// The task ended: the follower goes back to its packages and leaves the favour state.
    private func finish(_ outcome: FollowerCommandOutcome) {
        guard let follower = phase.follower else { return }
        release(follower)
        phase = .idle
        lastOutcome = outcome
        world?.endFavor(follower, announces: false)
    }

    /// Command mode ended without a command.
    private func end(_ follower: ReferenceKey, _ outcome: FollowerCommandOutcome) {
        phase = .idle
        lastOutcome = outcome
        world?.endFavor(follower, announces: true)
    }

    private func hold(_ follower: ReferenceKey) {
        world?.holdFollower(follower)
        world?.stopFollower(follower)
    }

    private func release(_ follower: ReferenceKey) {
        world?.releaseFollower(follower)
    }

    /// A spot on the ground counts as reached closer in than a thing to use.
    private func isInReach(_ follower: ReferenceKey, of task: FollowerCommandTask) -> Bool {
        guard let position = world?.followerCommandPosition(of: follower) else { return false }
        let reach = task.action == .moveTo ? settings.reach / 4 : settings.reach
        return simd_distance(position, task.target.position) <= reach
    }

    /// A point short of the target on the follower's side, so it stops in front of it.
    func approach(to target: SIMD3<Float>, from start: SIMD3<Float>?) -> SIMD3<Float> {
        guard let start else { return target }
        let offset = SIMD2(start.x - target.x, start.y - target.y)
        let length = simd_length(offset)
        guard length > 1e-3 else { return target }
        let moved = SIMD2(target.x, target.y) + offset / length * settings.reach * 0.75
        return SIMD3(moved.x, moved.y, target.z)
    }
}
