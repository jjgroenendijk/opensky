// SCEN scene: a quest-owned script of phases, actors, and actions. Phases,
// actors, and actions are runs whose order matters, so the decoder walks the
// fields in sequence. Layout and sources: docs/formats/scenes.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct ScenePhase: Equatable, Sendable {
    public var name: String?
    public var startConditions: [Condition] = []
    public var completionConditions: [Condition] = []
    /// WNAM, the editor width.
    public var editorWidth: UInt32?
}

nonisolated public struct SceneActor: Equatable, Sendable {
    /// ALID, a quest alias ID.
    public let aliasID: Int32
    /// LNAM: 0x01 no player activation, 0x02 optional.
    public var flags: UInt32?
    /// DNAM: pause and end bits for death, combat, dialogue, and observed combat.
    public var behaviorFlags: UInt32?
}

nonisolated public struct SceneDialogue: Equatable, Sendable {
    /// DATA, a DIAL.
    public var topic: FormID?
    /// HTID, the alias the speaker looks at.
    public var headtrackAliasID: Int32?
    public var loopingMax: Float?
    public var loopingMin: Float?
    /// DEMO, the emotion type index.
    public var emotionType: UInt32?
    public var emotionValue: UInt32?
}

nonisolated public enum SceneActionPayload: Equatable, Sendable {
    case dialogue(SceneDialogue)
    /// PNAM packages in order.
    case package([FormID])
    /// SNAM duration in seconds.
    case timer(Float?)
    /// An action type xEdit does not name.
    case unknown
}

nonisolated public struct SceneAction: Equatable, Sendable {
    /// ANAM type: 0 dialogue, 1 package, 2 timer. Others are kept.
    public let type: UInt16
    public var name: String?
    public var aliasID: Int32?
    /// LNAM. xEdit leaves it unnamed, so it stays raw.
    public var unknownLNAM: Data?
    public var index: UInt32?
    /// FNAM: 0x8000 face target, 0x10000 looping, 0x20000 headtrack player.
    public var flags: UInt32?
    public var startPhase: UInt32?
    public var endPhase: UInt32?
    public var payload: SceneActionPayload
}

/// VNAM: per-event behavior for all actors. Each value is 0 normal, 1 pause, 2 end, 3 don't set.
nonisolated public struct SceneActorBehavior: Equatable, Sendable {
    public let death: UInt32
    public let combat: UInt32
    public let dialogue: UInt32
    public let observeCombat: UInt32
}

nonisolated public struct Scene: Equatable, Sendable {
    public struct Flags: OptionSet, Equatable, Sendable {
        public let rawValue: UInt32

        public init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        public static let beginOnQuestStart = Flags(rawValue: 0x01)
        public static let stopQuestOnEnd = Flags(rawValue: 0x02)
        public static let showAllText = Flags(rawValue: 0x04)
        public static let repeatConditionsWhileTrue = Flags(rawValue: 0x08)
        public static let interruptible = Flags(rawValue: 0x10)
    }

    public let formID: FormID
    public let editorID: String?
    public let flags: Flags
    public let phases: [ScenePhase]
    public let actors: [SceneActor]
    public let actions: [SceneAction]
    /// PNAM, the owning QUST.
    public let quest: FormID?
    /// INAM.
    public let lastActionIndex: UInt32?
    public let actorBehavior: SceneActorBehavior?
    public let conditions: [Condition]
    public let scriptData: ScriptData
    public let skipped: FieldTally

    public init(record: ESMRecord) throws {
        var walk = try SceneFieldWalk(record: record)
        walk.run()
        formID = walk.fields.formID
        editorID = walk.editorID
        flags = Flags(rawValue: walk.flags)
        phases = walk.phases
        actors = walk.actors
        actions = walk.actions
        quest = walk.quest
        lastActionIndex = walk.lastActionIndex
        actorBehavior = walk.actorBehavior
        conditions = walk.conditions.conditions
        scriptData = walk.scriptData
        skipped = walk.fields.finish()
    }
}
