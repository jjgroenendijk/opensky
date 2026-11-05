// An actor's sound types (NPC_ CSDT) and the loops a living creature keeps playing:
// breath and hum (conscious loop) and the moving parts of a machine (movement loop).
// See docs/engine/actor-sounds.md.

import OpenSkyFormatsCore
import OpenSkyFormatsESM
import simd

/// The CSDT types an actor can carry; the UESP NPC_ page gives the numbers.
nonisolated public enum ActorSoundKind: UInt32, Sendable, CaseIterable {
    case idle = 0, aware, attack, hit, death, weapon, movementLoop, consciousLoop
}

/// One NPC_ record's sound data: its own list and its audio template (`CSCR`).
nonisolated public struct ActorSoundRecord: Equatable, Sendable {
    public var inheritsFrom: FormID?
    public var types: [ActorSoundType]

    public init(inheritsFrom: FormID?, types: [ActorSoundType]) {
        self.inheritsFrom = inheritsFrom
        self.types = types
    }
}

nonisolated public struct ActorSounds: Equatable, Sendable {
    public static let none = ActorSounds(types: [])
    public var types: [ActorSoundType]

    public init(types: [ActorSoundType]) {
        self.types = types
    }

    /// The sounds of `npc`. An audio template replaces the actor's own list, as the
    /// Creation Kit locks that list; a template can name another in turn.
    public static func of(_ npc: FormID, records: (FormID) -> ActorSoundRecord?) -> ActorSounds {
        var current = npc
        var visited: Set<FormID> = []
        while visited.insert(current).inserted, let record = records(current) {
            guard let template = record.inheritsFrom else {
                return ActorSounds(types: record.types)
            }
            current = template
        }
        return .none
    }

    /// Every sound of one type. An entry with a chance of 0 never plays.
    public func sounds(_ kind: ActorSoundKind) -> [FormID] {
        types.filter { $0.type == kind.rawValue }
            .flatMap(\.entries)
            .filter { ($0.chance ?? 100) > 0 }
            .compactMap(\.sound)
    }

    /// The loops that play now: the conscious loop while awake, the movement loop on top
    /// while the actor moves.
    public func loops(isConscious: Bool, isMoving: Bool) -> [FormID] {
        guard isConscious else { return [] }
        return sounds(.consciousLoop) + (isMoving ? sounds(.movementLoop) : [])
    }
}

/// One actor near the listener, as the loop plan reads it each frame.
nonisolated public struct ActorSoundSource: Equatable, Sendable {
    public var key: ReferenceKey
    public var position: SIMD3<Float>
    public var sounds: ActorSounds
    public var isConscious: Bool
    public var isMoving: Bool

    public init(
        key: ReferenceKey, position: SIMD3<Float>, sounds: ActorSounds,
        isConscious: Bool, isMoving: Bool
    ) {
        self.key = key
        self.position = position
        self.sounds = sounds
        self.isConscious = isConscious
        self.isMoving = isMoving
    }
}

/// One loop one actor plays.
nonisolated public struct ActorLoop: Hashable, Sendable {
    public var actor: ReferenceKey
    public var sound: FormID

    public init(actor: ReferenceKey, sound: FormID) {
        self.actor = actor
        self.sound = sound
    }
}

/// Which actor loops should play: those of the nearest actors in reach. Pure.
nonisolated public enum ActorLoopPlan {
    /// Units from the listener within which an actor's loops play; OpenSky's value.
    public static let reach: Float = 3000
    /// Actors whose loops play at once, nearest first; OpenSky's value.
    public static let actorLimit = 8

    public static func wanted(
        _ sources: [ActorSoundSource], listener: SIMD3<Float>
    ) -> [ActorLoop: SIMD3<Float>] {
        let near = sources
            .map { (source: $0, distance: simd_distance($0.position, listener)) }
            .filter { $0.distance <= reach && $0.distance.isFinite }
            .sorted { $0.distance < $1.distance }
            .prefix(actorLimit)
        var wanted: [ActorLoop: SIMD3<Float>] = [:]
        for (source, _) in near {
            let loops = source.sounds.loops(
                isConscious: source.isConscious, isMoving: source.isMoving
            )
            for sound in loops {
                wanted[ActorLoop(actor: source.key, sound: sound)] = source.position
            }
        }
        return wanted
    }
}
