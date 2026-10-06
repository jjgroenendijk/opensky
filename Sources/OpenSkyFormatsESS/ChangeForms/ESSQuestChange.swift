// `QUST` change data: runtime flags, script delay, stages, objectives, run data, and
// instances. See docs/formats/ess-change-forms.md#quests.

import Foundation

nonisolated public struct ESSQuestStage: Equatable, Sendable {
    public let index: Int16
    /// The stage's stored status byte; UESP calls it a boolean.
    public let isDone: Bool
}

/// An objective's two stored words. UESP does not name them.
nonisolated public struct ESSQuestObjective: Equatable, Sendable {
    public let first: UInt32
    public let second: UInt32
}

nonisolated public struct ESSQuestChange: Equatable, Sendable {
    public let form: ESSRefID
    public private(set) var formFlags: UInt32?
    /// The quest's runtime flags. UESP does not document their meaning.
    public private(set) var questFlags: UInt16?
    public private(set) var scriptDelay: Float?
    public private(set) var stages: [ESSQuestStage]?
    public private(set) var objectives: [ESSQuestObjective]?
    public private(set) var alreadyRun: Bool?
    public private(set) var status = ESSDecodeStatus.complete

    private typealias Flag = ESSChangeFlag.Quest

    /// The highest stage marked done, which is the quest's current stage.
    public var currentStage: Int16? {
        stages?.filter(\.isDone).map(\.index).max()
    }

    public init(_ change: ESSChangeForm) throws(ESSError) {
        guard change.type?.signature == "QUST" else {
            throw .invalidValue(context: "change form \(change.form) is not a quest")
        }
        form = change.form
        var reader = try ESSReader(change.data())
        try read(&reader, change: change)
        guard status.isComplete, !reader.isAtEnd else { return }
        // QUEST_SCRIPT has no documented data; a leftover tail is laid at its door.
        let blocker = change.has(Flag.script) ? "QUEST_SCRIPT" : "unread bytes"
        status = .partial(blockedBy: "\(blocker) (\(reader.bytesRemaining) bytes)")
    }

    private mutating func read(_ reader: inout ESSReader, change: ESSChangeForm) throws(ESSError) {
        if change.has(ESSChangeFlag.formFlags) {
            formFlags = try reader.uint32("form flags")
            _ = try reader.uint16("form flags")
        }
        if change.has(Flag.flags) {
            questFlags = try reader.uint16("quest flags")
        }
        if change.has(Flag.scriptDelay) {
            scriptDelay = try reader.float32("quest script delay")
        }
        if change.has(Flag.stages) {
            let count = try reader.count("quest stages", minimumElementSize: 3)
            var stages: [ESSQuestStage] = []
            for _ in 0 ..< count {
                try stages.append(ESSQuestStage(
                    index: reader.int16("quest stage"), isDone: reader.uint8("stage status") != 0
                ))
            }
            self.stages = stages
        }
        if change.has(Flag.objectives) {
            let count = try reader.count("quest objectives", minimumElementSize: 8)
            var objectives: [ESSQuestObjective] = []
            for _ in 0 ..< count {
                try objectives.append(ESSQuestObjective(
                    first: reader.uint32("objective"), second: reader.uint32("objective")
                ))
            }
            self.objectives = objectives
        }
        if change.has(Flag.runData) {
            try ESSQuestRunData.skip(&reader)
        }
        if change.has(Flag.instances) {
            try ESSQuestRunData.skipInstances(&reader)
        }
        if change.has(Flag.alreadyRun) {
            alreadyRun = try reader.uint8("quest already run") != 0
        }
    }
}

/// Quest run data and instance data: read to find their end, not mapped.
nonisolated enum ESSQuestRunData {
    static func skip(_ reader: inout ESSReader) throws(ESSError) {
        _ = try reader.uint8("run data")
        let itemCount = try reader.count32("run data items", minimumElementSize: 8)
        for _ in 0 ..< itemCount {
            _ = try reader.uint32("run data item")
            let refCount = try reader.uint8("run data item flag") == 0 ? 1 : 5
            try reader.skip(refCount * 3, "run data item")
        }
        let secondCount = try reader.count32("run data items 2", minimumElementSize: 7)
        try reader.skip(secondCount * 7, "run data items 2")
        guard try reader.uint8("run data flag") != 0 else { return }
        try reader.skip(8, "run data item 3")
        let dataCount = try reader.count32("run data item 3 data", minimumElementSize: 7)
        for _ in 0 ..< dataCount {
            let type = try reader.uint32("run data item 3 type")
            switch type {
            case 1, 2, 4: _ = try reader.refID("run data item 3")
            case 3: _ = try reader.uint32("run data item 3")
            default: throw .invalidValue(context: "quest run data item type \(type)")
            }
        }
    }

    static func skipInstances(_ reader: inout ESSReader) throws(ESSError) {
        _ = try reader.uint32("quest instances")
        let count = try reader.count("quest instances", minimumElementSize: 9)
        for _ in 0 ..< count {
            _ = try reader.uint32("quest instance")
            let first = try reader.count("quest instance refs", minimumElementSize: 7)
            try reader.skip(first * 7, "quest instance refs")
            let second = try reader.count("quest instance refs 2", minimumElementSize: 7)
            try reader.skip(second * 7 + 3, "quest instance refs 2")
        }
    }
}

/// `INFO` change data: the said-once flag carries no data of its own.
nonisolated public struct ESSTopicChange: Equatable, Sendable {
    public let form: ESSRefID
    public let saidOnce: Bool

    public init(_ change: ESSChangeForm) throws(ESSError) {
        guard change.type?.signature == "INFO" else {
            throw .invalidValue(context: "change form \(change.form) is not a topic info")
        }
        form = change.form
        saidOnce = change.has(ESSChangeFlag.Topic.saidOnce)
    }
}
