// What a bumped NPC does: says its bump line, waits `fBumpReactionSmallDelayTime`, steps
// aside by `fBumpReactionIdealMoveDist` (never less than `fBumpReactionMinMoveDist`), and
// keeps out of its package for `fBumpReactionSmallWaitTimer`. The settings come from the
// install; the order of the steps is OpenSky's reading (docs/engine/bump-reactions.md).

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import simd

nonisolated public struct BumpReactionSettings: Equatable, Sendable {
    public var idealMoveDistance: Float = 125
    public var minMoveDistance: Float = 75
    public var delaySeconds: Float = 1
    public var waitSeconds: Float = 3

    public static let vanilla = Self()

    public init() {}

    public static func resolve(store: GameSettingStore) -> Self {
        var settings = vanilla
        store.read("fBumpReactionIdealMoveDist", into: &settings, \.idealMoveDistance)
        store.read("fBumpReactionMinMoveDist", into: &settings, \.minMoveDistance)
        store.read("fBumpReactionSmallDelayTime", into: &settings, \.delaySeconds)
        store.read("fBumpReactionSmallWaitTimer", into: &settings, \.waitSeconds)
        return settings
    }

    /// How far a bumped actor steps: the ideal distance, raised to the minimum.
    public var moveDistance: Float {
        let ideal = idealMoveDistance.isFinite ? idealMoveDistance : 0
        let least = minMoveDistance.isFinite ? minMoveDistance : 0
        return max(ideal, least, 0)
    }
}

/// The player touching one NPC this frame.
nonisolated public struct BumpContact: Equatable, Sendable {
    public let actor: ReferenceKey
    public let actorFeet: SIMD3<Float>
    public let playerFeet: SIMD3<Float>

    public init(actor: ReferenceKey, actorFeet: SIMD3<Float>, playerFeet: SIMD3<Float>) {
        self.actor = actor
        self.actorFeet = actorFeet
        self.playerFeet = playerFeet
    }
}

/// What the bump rule asks of the world.
nonisolated public enum BumpCommand: Equatable, Sendable {
    /// Say the bump line (`ACAC`).
    case speak(ReferenceKey)
    case move(ReferenceKey, to: SIMD3<Float>)
}

/// The bumped actors and where each is in its reaction.
nonisolated public struct BumpReactions: Equatable, Sendable {
    private enum Stage: Equatable, Sendable {
        case delaying(until: Double, goal: SIMD3<Float>)
        case holding(until: Double)
    }

    private var stages: [ReferenceKey: Stage] = [:]
    /// Reactions started since the last reset, for the readout.
    public private(set) var reactionCount = 0

    public init() {}

    /// Actors held out of their package by a reaction.
    public var reactingActors: Set<ReferenceKey> {
        Set(stages.keys)
    }

    /// Starts a reaction for each contact whose actor is not already reacting.
    public mutating func note(
        _ contacts: [BumpContact], now: Double, settings: BumpReactionSettings
    ) -> [BumpCommand] {
        var commands: [BumpCommand] = []
        for contact in contacts where stages[contact.actor] == nil {
            let delay = Double(settings.delaySeconds.isFinite ? max(settings.delaySeconds, 0) : 0)
            stages[contact.actor] = .delaying(
                until: now + delay, goal: Self.goal(of: contact, distance: settings.moveDistance)
            )
            reactionCount += 1
            commands.append(.speak(contact.actor))
        }
        return commands
    }

    /// Moves reactions on. Returns the moves to start and the actors whose reaction ended.
    public mutating func advance(
        now: Double, settings: BumpReactionSettings
    ) -> (commands: [BumpCommand], finished: [ReferenceKey]) {
        var commands: [BumpCommand] = []
        var finished: [ReferenceKey] = []
        let wait = Double(settings.waitSeconds.isFinite ? max(settings.waitSeconds, 0) : 0)
        for actor in stages.keys.sorted() {
            switch stages[actor] {
            case let .delaying(until, goal)? where now >= until:
                stages[actor] = .holding(until: now + wait)
                commands.append(.move(actor, to: goal))
            case let .holding(until)? where now >= until:
                stages[actor] = nil
                finished.append(actor)
            default:
                break
            }
        }
        return (commands, finished)
    }

    /// Drops `actor`'s reaction, such as when it starts a fight or unloads.
    public mutating func cancel(_ actor: ReferenceKey) {
        stages[actor] = nil
    }

    public mutating func reset() {
        stages = [:]
        reactionCount = 0
    }

    /// A point `distance` from the actor, straight away from the player on the ground.
    static func goal(of contact: BumpContact, distance: Float) -> SIMD3<Float> {
        let offset = contact.actorFeet - contact.playerFeet
        let planar = SIMD2(offset.x, offset.y)
        let direction = simd_length(planar) > 1e-3 ? simd_normalize(planar) : SIMD2<Float>(1, 0)
        return contact.actorFeet + SIMD3(direction.x, direction.y, 0) * distance
    }
}
