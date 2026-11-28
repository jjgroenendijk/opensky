// The movement loop of a melee actor in reach: each pass rolls circle and fall back,
// then back off, and runs the move that starts until it ends.
// See docs/formats/combat-style.md#close-range-movement.

import Foundation
import OpenSkyCombatInterface
import OpenSkyConditions
import simd

nonisolated struct CombatCloseMoveLoop: Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case backOff, circle, fallBack
    }

    struct Move: Equatable, Sendable {
        var kind: Kind
        var destination: SIMD3<Float>
        /// The other circle side, tried once when no path reaches the first.
        var alternate: SIMD3<Float>?
        var startedAt: Float
        var nextCheck: Float
        var lastDistance: Float
    }

    /// A move closer than this to its point has arrived. Ours.
    static let arrivalRadius: Float = 32
    /// A move that has not arrived after this long fails. Ours.
    static let timeoutSeconds: Float = 5
    /// Faster than this away from the actor, in units a second, a target moves away. Ours.
    static let movingAwaySpeed: Float = 1

    private(set) var move: Move?
    /// The time of the next pass, on the phase clock.
    private(set) var nextPass: Float = 0
    /// The choices left in this pass, tried after a refused path.
    private(set) var pending: [Kind] = []
    /// True through the wait after a fallback, which the actor spends where it stopped.
    private(set) var waitsAfterFallback = false
    /// Moves started since construction, for the readout.
    private(set) var startedCount = 0

    init(startedCount: Int = 0) {
        self.startedCount = startedCount
    }

    /// Whether the actor keeps to its move, or to the wait after a fallback, rather than
    /// closing in again once it is out of reach.
    func holdsPosition(now: Float) -> Bool {
        move != nil || (waitsAfterFallback && now < nextPass)
    }

    /// One step of the loop at phase time `now`. Returns a command only when the actor
    /// should move to a new point or stop.
    mutating func advance(
        now: Float, inputs: CombatBehaviorInputs, rules: Rules, random: inout ConditionRandom
    ) -> CombatMovementCommand? {
        if let running = move {
            return check(running, now: now, inputs: inputs, rules: rules)
        }
        guard now >= nextPass else { return nil }
        if pending.isEmpty {
            pending = pass(rules.settings, random: &random)
        }
        while !pending.isEmpty {
            let kind = pending.removeFirst()
            if kind == .backOff, Self.roll(rules.settings.backOffChance, &random) == false {
                continue
            }
            let points = points(of: kind, inputs: inputs, rules: rules, random: &random)
            if let first = points.first {
                let check = kind == .fallBack ? rules.settings.fallbackFirstCheckSeconds : rules
                    .settings.checkSeconds
                move = Move(
                    kind: kind, destination: first, alternate: points.dropFirst().first,
                    startedAt: now, nextCheck: now + check, lastDistance: inputs.distance
                )
                startedCount += 1
                return .reposition(first)
            }
        }
        nextPass = now + rules.settings.pauseSeconds
        return nil
    }

    /// No path reaches the move's point. A circle tries its other side once; any other move
    /// fails, and the next step tries what is left of the pass.
    mutating func refused(now: Float) -> CombatMovementCommand? {
        guard var running = move else { return nil }
        guard let alternate = running.alternate else {
            move = nil
            nextPass = now
            return nil
        }
        running.destination = alternate
        running.alternate = nil
        move = running
        return .reposition(alternate)
    }

    /// The circle and fallback rolls, each on its own, in a random order when both pass.
    /// Back off comes last, with its own roll when it is tried.
    private func pass(
        _ settings: CombatCloseRangeSettings, random: inout ConditionRandom
    ) -> [Kind] {
        var passed: [Kind] = []
        if Self.roll(settings.circleChance, &random) {
            passed.append(.circle)
        }
        if Self.roll(settings.fallbackChance, &random) {
            passed.append(.fallBack)
        }
        if passed.count == 2, Self.roll(0.5, &random) {
            passed.reverse()
        }
        return passed + [.backOff]
    }

    static func roll(_ chance: Float, _ random: inout ConditionRandom) -> Bool {
        Float(random.percent()) / 100 < chance
    }
}

// MARK: - Starting a move

nonisolated extension CombatCloseMoveLoop {
    /// What one actor's loop needs beside its inputs.
    struct Rules: Equatable, Sendable {
        var settings: CombatCloseRangeSettings
        /// `reach + inner advance radius`: the distance a back off walks out to.
        var backOffDistance: Float
    }

    /// The points a move of `kind` could walk to, the preferred first. Empty when it
    /// cannot start.
    private func points(
        of kind: Kind, inputs: CombatBehaviorInputs, rules: Rules, random: inout ConditionRandom
    ) -> [SIMD3<Float>] {
        let settings = rules.settings
        guard
            abs(inputs.facingError) <= Self.radians(settings.startFacingDegrees),
            !Self.movesAway(inputs) else { return [] }
        switch kind {
        case .backOff:
            guard inputs.distance < 0.75 * rules.backOffDistance else { return [] }
            return [inputs.retreatPoint(to: rules.backOffDistance)]
        case .circle:
            return circlePoints(inputs, settings: settings, random: &random)
        case .fallBack:
            return fallBackPoint(inputs, settings: settings).map { [$0] } ?? []
        }
    }

    /// The vector from the target to the actor, at least `reach` long, turned about the
    /// target by the circle angle. The first point is the side the roll picked.
    private func circlePoints(
        _ inputs: CombatBehaviorInputs, settings: CombatCloseRangeSettings,
        random: inout ConditionRandom
    ) -> [SIMD3<Float>] {
        let offset = inputs.actorPosition - inputs.targetPosition
        var planar = SIMD2(offset.x, offset.y)
        let length = max(simd_length(planar), inputs.reach)
        planar = simd_length(planar) > 0 ? simd_normalize(planar) : SIMD2(1, 0)
        let spread = max(0, settings.circleAngleMax - settings.circleAngleMin)
        var degrees = settings.circleAngleMin + spread * Float(random.percent()) / 100
        if inputs.targetIsPlayer {
            degrees *= settings.circleAnglePlayerMult
        }
        let least = inputs.actorRadius * settings.circleMinDistanceRadiusMult
            / max(inputs.distance, 1)
        let angle = max(Self.radians(degrees), least)
        guard angle <= Self.radians(settings.circleAngleCap) else { return [] }
        let sides = Self.roll(0.5, &random) ? [angle, -angle] : [-angle, angle]
        return sides.compactMap { turn in
            let turned = SIMD2(
                planar.x * cos(turn) - planar.y * sin(turn),
                planar.x * sin(turn) + planar.y * cos(turn)
            ) * length
            if let yaw = inputs.targetYaw {
                let facing = SIMD2(cos(yaw), sin(yaw))
                let off = acos(min(max(simd_dot(facing, simd_normalize(turned)), -1), 1))
                guard off <= Self.radians(settings.circleTargetFacingDegrees) else { return nil }
            }
            return SIMD3(
                inputs.targetPosition.x + turned.x, inputs.targetPosition.y + turned.y,
                inputs.actorPosition.z
            )
        }
    }

    /// Straight away from the target to `reach + max(fallback distance, 2 * radius)`, while
    /// the target faces the actor and that is further than now.
    private func fallBackPoint(
        _ inputs: CombatBehaviorInputs, settings: CombatCloseRangeSettings
    ) -> SIMD3<Float>? {
        if let yaw = inputs.targetYaw {
            let toActor = inputs.actorPosition - inputs.targetPosition
            let planar = SIMD2(toActor.x, toActor.y)
            guard simd_length(planar) > 0 else { return nil }
            let off = acos(min(max(
                simd_dot(SIMD2(cos(yaw), sin(yaw)), simd_normalize(planar)),
                -1
            ), 1))
            guard off <= Self.radians(settings.fallbackTargetFacingDegrees) else { return nil }
        }
        let wanted = inputs.reach + max(settings.fallbackDistance, 2 * inputs.actorRadius)
        guard wanted > inputs.distance else { return nil }
        return inputs.retreatPoint(to: wanted)
    }

    static func movesAway(_ inputs: CombatBehaviorInputs) -> Bool {
        let offset = inputs.targetPosition - inputs.actorPosition
        let planar = SIMD2(offset.x, offset.y)
        guard simd_length(planar) > 0 else { return false }
        let velocity = SIMD2(inputs.targetVelocity.x, inputs.targetVelocity.y)
        return simd_dot(velocity, simd_normalize(planar)) > movingAwaySpeed
    }

    static func radians(_ degrees: Float) -> Float {
        degrees * .pi / 180
    }
}

// MARK: - Running a move

nonisolated extension CombatCloseMoveLoop {
    private enum Outcome {
        case running, succeeded, cancelled
    }

    private mutating func check(
        _ running: Move, now: Float, inputs: CombatBehaviorInputs, rules: Rules
    ) -> CombatMovementCommand? {
        guard now >= running.nextCheck else { return nil }
        let outcome = outcome(of: running, now: now, inputs: inputs, rules: rules)
        guard outcome != .running else {
            var next = running
            next.nextCheck = now + rules.settings.checkSeconds
            next.lastDistance = inputs.distance
            move = next
            return nil
        }
        move = nil
        nextPass = now + wait(after: running.kind, outcome: outcome, settings: rules.settings)
        waitsAfterFallback = running.kind == .fallBack
        pending = []
        return .hold
    }

    private func outcome(
        of running: Move, now: Float, inputs: CombatBehaviorInputs, rules: Rules
    ) -> Outcome {
        let towardTarget = inputs.distance < running.lastDistance - 1
        let offset = running.destination - inputs.actorPosition
        let arrived = simd_length(SIMD2(offset.x, offset.y)) <= Self.arrivalRadius
        let ahead = inputs.targetPosition + inputs.targetVelocity * 0.5 - inputs.actorPosition
        let aheadDistance = simd_length(SIMD2(ahead.x, ahead.y))
        switch running.kind {
        case .backOff:
            if arrived || towardTarget || inputs.distance >= rules.backOffDistance {
                return .succeeded
            }
        case .circle:
            if arrived || aheadDistance > rules.settings.circleBreakDistance {
                return .succeeded
            }
        case .fallBack:
            if arrived {
                return .succeeded
            }
            if towardTarget || aheadDistance > rules.settings.fallbackBreakDistance {
                return .cancelled
            }
        }
        return now - running.startedAt >= Self.timeoutSeconds ? .cancelled : .running
    }

    private func wait(
        after kind: Kind, outcome: Outcome, settings: CombatCloseRangeSettings
    ) -> Float {
        guard kind == .fallBack else { return 0 }
        return outcome == .succeeded ? settings.fallbackWaitSeconds : settings
            .cancelledFallbackWaitSeconds
    }
}
