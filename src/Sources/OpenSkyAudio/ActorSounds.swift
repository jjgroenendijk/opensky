// An actor's sound types (NPC_ CSDT): the one its graph's `enum_` event asks for, and the
// conscious loop a living creature keeps playing. See docs/engine/actor-sounds.md.

import OpenSkyFormatsCore
public import OpenSkyFormatsESM
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

    /// The sounds of `npc`: its own list, or the list of its audio template, which the
    /// Creation Kit locks the own list to. A template that inherits in turn gives none.
    public static func of(_ npc: FormID, records: (FormID) -> ActorSoundRecord?) -> ActorSounds {
        guard let record = records(npc) else { return .none }
        guard let template = record.inheritsFrom else { return ActorSounds(types: record.types) }
        guard let inherited = records(template), inherited.inheritsFrom == nil else {
            return .none
        }
        return ActorSounds(types: inherited.types)
    }

    /// Every sound of one type. An entry with a chance of 0 never plays.
    public func sounds(_ kind: ActorSoundKind) -> [FormID] {
        types.filter { $0.type == kind.rawValue }
            .flatMap(\.entries)
            .filter { ($0.chance ?? 100) > 0 }
            .compactMap(\.sound)
    }

    /// The sound one event of `kind` plays: the entries in order of chance, lowest
    /// first, each with its own roll in 0...99, and the first roll below its chance wins.
    /// Nil when no roll passes.
    public func pick(_ kind: ActorSoundKind, roll: () -> Int) -> FormID? {
        let entries = types.filter { $0.type == kind.rawValue }.flatMap(\.entries)
        let byChance = entries.indices.sorted { left, right in
            let chances = (entries[left].chance ?? 100, entries[right].chance ?? 100)
            return chances.0 == chances.1 ? left < right : chances.0 < chances.1
        }
        for index in byChance {
            let entry = entries[index]
            if roll() < Int(entry.chance ?? 100) {
                return entry.sound
            }
        }
        return nil
    }

    /// The loops that play now: the conscious loop while the actor is awake.
    public func loops(isConscious: Bool) -> [FormID] {
        isConscious ? sounds(.consciousLoop) : []
    }
}

/// One actor near the listener, as the loop plan reads it each frame.
nonisolated public struct ActorSoundSource: Equatable, Sendable {
    public var key: ReferenceKey
    public var position: SIMD3<Float>
    public var sounds: ActorSounds
    public var isConscious: Bool

    public init(
        key: ReferenceKey, position: SIMD3<Float>, sounds: ActorSounds, isConscious: Bool
    ) {
        self.key = key
        self.position = position
        self.sounds = sounds
        self.isConscious = isConscious
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
            for sound in source.sounds.loops(isConscious: source.isConscious) {
                wanted[ActorLoop(actor: source.key, sound: sound)] = source.position
            }
        }
        return wanted
    }
}
