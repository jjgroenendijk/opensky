// The flanking loop of an NPC whose style has the flanking flag: a stalk that keeps a band
// around the target, then the flank, chase, flank distant, and watch choices.
// See docs/engine/combat-movement.md#flanking.

import Foundation
import OpenSkyCombatInterface
import simd

nonisolated struct CombatFlankLoop: Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case stalk, flank, chase, flankDistant, watch
    }

    struct Move: Equatable, Sendable {
        var kind: Kind
        var destination: SIMD3<Float>?
        var startedAt: Float
        /// The stalk is walking back into its band.
        var isJogging = false
    }

    /// What the loop asks the mover for.
    struct Order: Equatable, Sendable {
        var command: CombatMovementCommand
        var pace: CombatPace?
        /// The bearing of the place a flank books.
        var booksPlace: Float?
    }

    /// What one step of the loop reads beside the inputs.
    struct Rules: Sendable {
        var settings: CombatFlankSettings
        var strikingDistance: Float
        /// The NPC is in an attack, which keeps a stalk past its time.
        var isAttacking: Bool
        /// The free place at the NPC's reach, and the approach pace.
        var goal: (point: SIMD3<Float>, bearing: Float)?
        /// Where the chase walks: the advance's point.
        var chasePoint: SIMD3<Float>
        var approachPace: CombatPace
    }

    static let choices: [Kind] = [.flank, .chase, .flankDistant, .watch]

    private(set) var move: Move?
    private(set) var clock: Float = 0
    /// The flank choices left, tried after a refused path. Nil while stalking or moving.
    private(set) var pending: [Kind]?
    /// Moves started since construction, for the readout.
    private(set) var startedCount = 0

    mutating func tick(_ seconds: Float) {
        clock += seconds
    }

    /// One step: runs the move under way, or starts the next one.
    mutating func advance(_ inputs: CombatBehaviorInputs, rules: Rules) -> Order? {
        if let running = move {
            return check(running, inputs: inputs, rules: rules)
        }
        if pending == nil {
            if inputs.distance < inputs.reach + rules.settings.stalkBand {
                return begin(.stalk, destination: nil)
            }
            pending = Self.choices
        }
        while let kind = pending?.first {
            pending?.removeFirst()
            if let order = start(kind, inputs: inputs, rules: rules) {
                pending = nil
                return order
            }
        }
        pending = nil
        return nil
    }

    /// No path reaches the move's point: it fails, and the next choice runs.
    mutating func refused() {
        guard let running = move, running.kind != .stalk else { return }
        move = nil
        pending = Array(Self.choices.drop { $0 != running.kind }.dropFirst())
    }

    /// Ends the loop, for an NPC that leaves the flanking branch.
    mutating func reset() {
        move = nil
        pending = nil
    }

    private mutating func begin(_ kind: Kind, destination: SIMD3<Float>?) -> Order? {
        move = Move(kind: kind, destination: destination, startedAt: clock)
        startedCount += 1
        return kind == .stalk ? nil : Order(command: .hold)
    }

    private mutating func start(
        _ kind: Kind, inputs: CombatBehaviorInputs, rules: Rules
    ) -> Order? {
        switch kind {
        case .flank:
            guard let goal = rules.goal, fitsAngle(goal.bearing, inputs: inputs, rules: rules)
            else { return nil }
            _ = begin(.flank, destination: goal.point)
            return Order(
                command: .reposition(goal.point), pace: rules.approachPace,
                booksPlace: goal.bearing
            )
        case .chase:
            let point = rules.chasePoint
            _ = begin(.chase, destination: point)
            return Order(
                command: .approach(point), pace: rules.approachPace,
                booksPlace: rules.goal?.bearing
            )
        case .flankDistant:
            guard rules.settings.flankDistance > 0 else { return nil }
            let point = CombatPathMoves.point(
                inputs, turnedBy: 0, radius: rules.settings.flankDistance
            )
            _ = begin(.flankDistant, destination: point)
            return Order(command: .reposition(point), pace: .run)
        case .watch, .stalk:
            return begin(.watch, destination: nil)
        }
    }

    /// Within the any-angle distance a goal fits; further out it must lie within the angle
    /// limit of the NPC's own bearing.
    private func fitsAngle(
        _ bearing: Float, inputs: CombatBehaviorInputs, rules: Rules
    ) -> Bool {
        guard
            let limit = rules.settings.angleLimit(beyondReach: inputs.distance - inputs.reach)
        else { return true }
        let offset = inputs.actorPosition - inputs.targetPosition
        let own = atan2f(offset.y, offset.x)
        return abs(CombatPlaceBook.turn(bearing - own)) <= limit
    }
}

// MARK: - Running a move

nonisolated extension CombatFlankLoop {
    private mutating func check(
        _ running: Move, inputs: CombatBehaviorInputs, rules: Rules
    ) -> Order? {
        let elapsed = clock - running.startedAt
        switch running.kind {
        case .stalk:
            return checkStalk(running, elapsed: elapsed, inputs: inputs, rules: rules)
        case .watch:
            if elapsed >= rules.settings.watchSeconds {
                move = nil
            }
            return nil
        case .flank, .chase, .flankDistant:
            let arrived = running.kind != .chase && running.destination.map {
                let offset = $0 - inputs.actorPosition
                return simd_length(SIMD2(offset.x, offset.y)) <= CombatCloseMoveLoop.arrivalRadius
            } ?? true
            let caught = running.kind == .chase && inputs.distance <= rules.strikingDistance
            let timedOut = elapsed >= CombatCloseMoveLoop.timeoutSeconds
            guard arrived || caught || timedOut else { return nil }
            move = nil
            if running.kind == .flank, inputs.distance > rules.strikingDistance {
                return start(.chase, inputs: inputs, rules: rules)
            }
            return timedOut ? Order(command: .hold) : nil
        }
    }

    /// The stalk ends at its limit, or once its time is over while the NPC is not
    /// attacking. Meanwhile it jogs back from beyond its band. It does not walk out from
    /// inside the reach, because the attack loop needs the NPC there.
    private mutating func checkStalk(
        _ running: Move, elapsed: Float, inputs: CombatBehaviorInputs, rules: Rules
    ) -> Order? {
        let settings = rules.settings
        if
            elapsed >= settings.stalkLimitSeconds
            || (elapsed >= settings.stalkSeconds && !rules.isAttacking)
        {
            move = nil
            pending = Self.choices
            return running.isJogging ? Order(command: .hold) : nil
        }
        let inBand = inputs.distance <= inputs.reach + settings.stalkBand
        guard inBand == running.isJogging else { return nil }
        var next = running
        next.isJogging = !inBand
        move = next
        guard !inBand else { return Order(command: .hold) }
        let middle = inputs.reach + settings.stalkBand / 2
        return Order(
            command: .reposition(CombatPathMoves.point(inputs, turnedBy: 0, radius: middle)),
            pace: .fastWalk
        )
    }
}
