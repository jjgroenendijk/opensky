// IDLP, TRNS, SOCL, and AVDM chunks: the idle each actor plays, the running scripted
// moves, each actor's social timers, and damage an imported save gave an actor. Each
// merges into the `RDLT` deltas by key.
// Layout: docs/formats/opensky-save-world-chunks.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyQuestsInterface
import OpenSkyScriptingInterface
import OpenSkyWorldInterface
import OpenSkyWorldState

nonisolated enum OpenSkySaveRunningStateWriter {
    static func write(_ entries: [WorldStateSnapshotEntry], into writer: inout BinaryWriter) {
        let tags = OpenSkySaveFormat.ChunkTag.self
        OpenSkySaveStoryWriter.writeStory(
            (SavedIdlePlay.self, tags.idlePlays), entries, &writer
        ) { play, payload in
            payload.writeString(play.idle.plugin)
            payload.writeUInt32(play.idle.objectID)
            writeOptionalKey(play.target, into: &payload)
        }
        OpenSkySaveStoryWriter.writeStory(
            (SavedTranslation.self, tags.translations), entries, &writer
        ) { move, payload in
            for vector in [move.position, move.rotation, move.targetPosition, move.targetRotation] {
                writeVector(vector, into: &payload)
            }
            payload.writeFloat32(move.speed)
            payload.writeFloat32(move.maxRotationSpeed)
            payload.writeUInt8(move.sentAlmostComplete ? 1 : 0)
        }
        OpenSkySaveStoryWriter.writeStory(
            (SavedSocialState.self, tags.socialStates), entries, &writer
        ) { social, payload in
            writeSocial(social, into: &payload)
        }
        OpenSkySaveStoryWriter.writeStory(
            (ImportedActorDamage.self, tags.importedDamage), entries, &writer
        ) { damage, payload in
            payload.writeFloat32(damage.amounts.health)
            payload.writeFloat32(damage.amounts.magicka)
            payload.writeFloat32(damage.amounts.stamina)
        }
    }

    private static func writeSocial(_ social: SavedSocialState, into payload: inout BinaryWriter) {
        let times = [social.socialTimer, social.recentTimer, social.bodyCheckAge]
        var flags: UInt8 = 0
        for (bit, time) in times.enumerated() where time != nil {
            flags |= 1 << UInt8(bit)
        }
        if social.conversation != nil {
            flags |= OpenSkySaveFormat.SocialFlag.conversation
        }
        payload.writeUInt8(flags)
        for time in times.compactMap(\.self) {
            payload.writeUInt64(time.bitPattern)
        }
        guard let talk = social.conversation else { return }
        payload.writeKey(talk.partner)
        payload.writeUInt8(talk.phase.rawValue)
        payload.writeUInt64(talk.age.bitPattern)
        payload.writeUInt64(talk.answerSeconds.bitPattern)
        payload.writeUInt8(talk.goal == nil ? 0 : 1)
        if let goal = talk.goal {
            writeVector(goal, into: &payload)
        }
    }

    private static func writeOptionalKey(_ key: ReferenceKey?, into payload: inout BinaryWriter) {
        payload.writeUInt8(key == nil ? 0 : 1)
        if let key {
            payload.writeKey(key)
        }
    }

    private static func writeVector(_ vector: SIMD3<Float>, into payload: inout BinaryWriter) {
        payload.writeFloat32(vector.x)
        payload.writeFloat32(vector.y)
        payload.writeFloat32(vector.z)
    }
}

nonisolated extension OpenSkySaveStoryDecoder {
    static func decodeIdlePlays(_ payload: Data) throws -> [SaveStoryEntry<SavedIdlePlay>] {
        try decode(
            payload, tag: OpenSkySaveFormat.ChunkTag.idlePlays,
            minimumSize: OpenSkySaveFormat.minimumIdlePlayEntrySize
        ) { reader in
            let plugin = try reader.string("IDLP plugin")
            let objectID = try reader.uint32("IDLP object ID")
            let target = try optionalKey(&reader, "IDLP target")
            return SavedIdlePlay(
                idle: ResolvedFormID(plugin: plugin, objectID: objectID), target: target
            )
        }
    }

    static func decodeTranslations(_ payload: Data) throws -> [SaveStoryEntry<SavedTranslation>] {
        try decode(
            payload, tag: OpenSkySaveFormat.ChunkTag.translations,
            minimumSize: OpenSkySaveFormat.translationEntrySize
        ) { reader in
            try SavedTranslation(
                position: vector(&reader, "TRNS position"),
                rotation: vector(&reader, "TRNS rotation"),
                targetPosition: vector(&reader, "TRNS target position"),
                targetRotation: vector(&reader, "TRNS target rotation"),
                speed: reader.float32("TRNS speed"),
                maxRotationSpeed: reader.float32("TRNS max rotation speed"),
                sentAlmostComplete: reader.bool("TRNS almost complete")
            )
        }
    }

    /// A time that is not finite is dropped, so that timer starts empty.
    static func decodeSocialStates(_ payload: Data) throws -> [SaveStoryEntry<SavedSocialState>] {
        try decode(
            payload, tag: OpenSkySaveFormat.ChunkTag.socialStates,
            minimumSize: OpenSkySaveFormat.minimumSocialStateEntrySize
        ) { reader in
            let flags = try reader.uint8("SOCL flags")
            var times: [Double?] = []
            for bit in 0 ..< 3 {
                let present = flags & (1 << UInt8(bit)) != 0
                try times.append(present ? finite(reader.uint64("SOCL time")) : nil)
            }
            var social = SavedSocialState(
                socialTimer: times[0], recentTimer: times[1], bodyCheckAge: times[2]
            )
            if flags & OpenSkySaveFormat.SocialFlag.conversation != 0 {
                social.conversation = try conversation(&reader)
            }
            return social
        }
    }

    /// A negative or not finite amount becomes 0.
    static func decodeImportedDamage(
        _ payload: Data
    ) throws -> [SaveStoryEntry<ImportedActorDamage>] {
        try decode(
            payload, tag: OpenSkySaveFormat.ChunkTag.importedDamage,
            minimumSize: OpenSkySaveFormat.minimumImportedDamageEntrySize
        ) { reader in
            try ImportedActorDamage(amounts: ActorValues(
                health: reader.float32("AVDM health"),
                magicka: reader.float32("AVDM magicka"),
                stamina: reader.float32("AVDM stamina")
            ))
        }
    }

    private static func conversation(
        _ reader: inout SaveReader
    ) throws -> SavedSocialState.Conversation? {
        let partner = try OpenSkySaveEntryDecoder.decodeKey(&reader)
        let raw = try reader.uint8("SOCL phase")
        guard let phase = SocialConversation.Phase(rawValue: raw) else {
            throw OpenSkySaveError.invalidValue(context: "SOCL phase \(raw) is unknown")
        }
        let age = try finite(reader.uint64("SOCL age"))
        let answer = try finite(reader.uint64("SOCL answer seconds"))
        let goal = try reader.bool("SOCL has goal") ? vector(&reader, "SOCL goal") : nil
        guard let age, let answer else { return nil }
        return SavedSocialState.Conversation(
            partner: partner, phase: phase, age: age, answerSeconds: answer, goal: goal
        )
    }

    private static func finite(_ bits: UInt64) -> Double? {
        let value = Double(bitPattern: bits)
        return value.isFinite ? value : nil
    }

    private static func optionalKey(
        _ reader: inout SaveReader, _ context: String
    ) throws -> ReferenceKey? {
        try reader.bool(context) ? OpenSkySaveEntryDecoder.decodeKey(&reader) : nil
    }

    private static func vector(
        _ reader: inout SaveReader,
        _ context: String
    ) throws -> SIMD3<Float> {
        try SIMD3(reader.float32(context), reader.float32(context), reader.float32(context))
    }
}

nonisolated extension OpenSkySaveDecoder {
    /// The running-state chunks. False for any other tag.
    static func applyRunningState(tag: String, payload: Data, to body: inout Body) throws -> Bool {
        switch tag {
        case OpenSkySaveFormat.ChunkTag.idlePlays:
            body.side.idlePlays = try OpenSkySaveStoryDecoder.decodeIdlePlays(payload)
        case OpenSkySaveFormat.ChunkTag.translations:
            body.side.translations = try OpenSkySaveStoryDecoder.decodeTranslations(payload)
        case OpenSkySaveFormat.ChunkTag.socialStates:
            body.side.socialStates = try OpenSkySaveStoryDecoder.decodeSocialStates(payload)
        case OpenSkySaveFormat.ChunkTag.importedDamage:
            body.side.importedDamage = try OpenSkySaveStoryDecoder.decodeImportedDamage(payload)
        default:
            return false
        }
        return true
    }
}

nonisolated extension OpenSkySaveDecoder.Body {
    static func mergeRunningState(
        _ body: Self, into entries: [WorldStateSnapshotEntry]
    ) -> [WorldStateSnapshotEntry] {
        var merged = OpenSkySaveDeltaMerge.merge(body.side.idlePlays, into: entries)
        merged = OpenSkySaveDeltaMerge.merge(body.side.translations, into: merged)
        merged = OpenSkySaveDeltaMerge.merge(body.side.importedDamage, into: merged)
        return OpenSkySaveDeltaMerge.merge(body.side.socialStates, into: merged)
    }
}
