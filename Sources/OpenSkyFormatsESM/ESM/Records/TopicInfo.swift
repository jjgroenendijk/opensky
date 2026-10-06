// INFO dialogue response set under a DIAL topic. TRDT opens a response run;
// NAM1/NAM2/NAM3 and idle links extend it until the next TRDT.
// Layout and sources: docs/formats/dialogue.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct TopicInfo: Sendable {
    public struct Flags: OptionSet, Equatable, Sendable {
        public let rawValue: UInt16

        public init(rawValue: UInt16) {
            self.rawValue = rawValue
        }

        public static let goodbye = Flags(rawValue: 1 << 0)
        public static let random = Flags(rawValue: 1 << 1)
        public static let sayOnce = Flags(rawValue: 1 << 2)
        public static let requiresPlayerActivation = Flags(rawValue: 1 << 3)
        public static let infoRefusal = Flags(rawValue: 1 << 4)
        public static let randomEnd = Flags(rawValue: 1 << 5)
        public static let invisibleContinue = Flags(rawValue: 1 << 6)
        public static let walkAway = Flags(rawValue: 1 << 7)
        public static let walkAwayInvisibleInMenu = Flags(rawValue: 1 << 8)
        public static let forceSubtitle = Flags(rawValue: 1 << 9)
        public static let canMoveWhileGreeting = Flags(rawValue: 1 << 10)
        public static let noLipFile = Flags(rawValue: 1 << 11)
        public static let requiresPostProcessing = Flags(rawValue: 1 << 12)
        public static let hasAudioOutputOverride = Flags(rawValue: 1 << 13)
        public static let spendsFavorPoints = Flags(rawValue: 1 << 14)
    }

    public enum FavorLevel: Equatable, Sendable {
        case none
        case small
        case medium
        case large
        case unknown(UInt8)

        public init(rawValue: UInt8) {
            switch rawValue {
            case 0: self = .none
            case 1: self = .small
            case 2: self = .medium
            case 3: self = .large
            default: self = .unknown(rawValue)
            }
        }
    }

    public struct Response: Equatable, Sendable {
        public enum Emotion: Equatable, Sendable {
            case neutral
            case anger
            case disgust
            case fear
            case sad
            case happy
            case surprise
            case puzzled
            case unknown(UInt32)

            public init(rawValue: UInt32) {
                switch rawValue {
                case 0: self = .neutral
                case 1: self = .anger
                case 2: self = .disgust
                case 3: self = .fear
                case 4: self = .sad
                case 5: self = .happy
                case 6: self = .surprise
                case 7: self = .puzzled
                default: self = .unknown(rawValue)
                }
            }
        }

        public let emotion: Emotion
        public let emotionValue: UInt32
        public let number: UInt8
        public let sound: FormID?
        public let usesEmotionAnimation: Bool
        public var text: LString?
        public var scriptNotes: String?
        public var edits: String?
        public var speakerIdle: FormID?
        public var listenerIdle: FormID?
    }

    public private(set) var formID: FormID
    public let editorID: String?
    public let flags: Flags
    /// DATA only, absent from ENAM-era records.
    public let legacyDialogueTab: UInt16?
    /// DATA days or ENAM's scaled day fraction, normalized to hours.
    public let resetHours: Float
    public private(set) var previousTopic: FormID?
    public private(set) var previousInfo: FormID?
    public let favorLevel: FavorLevel
    public private(set) var topicLinks: [FormID]
    public private(set) var sharedInfo: FormID?
    public let responses: [Response]
    public let conditions: ConditionList
    public let prompt: LString?
    public private(set) var speaker: FormID?
    public private(set) var walkAwayTopic: FormID?
    public private(set) var audioOutputOverride: FormID?
    /// VMAD's script list, including the decoded INFO fragment tail.
    public let script: ScriptData
    public let skipped: DialogueTally

    /// Result-script fragments, from the VMAD tail rather than from a field of
    /// their own. Empty when the response carries no result script, and also
    /// when its fragment tail failed to decode (`script.skipped` records that).
    public var fragments: [TopicInfoFragment] {
        script.infoFragments?.fragments ?? []
    }

    /// The generated result script, "TIF_<editorID>_<formID>" by convention, or
    /// nil when the response carries no fragment at all.
    public var fragmentScriptName: String? {
        guard
            let section = script.infoFragments, !section.isEmpty,
            !section.fileName.isEmpty
        else {
            return nil
        }
        return section.fileName
    }

    public init(record: ESMRecord, localized: Bool = false) throws {
        guard record.type == "INFO" else {
            throw ESMError.malformed("expected INFO record, got \(record.type)")
        }
        formID = FormID(record.formID)
        var contents = Contents(localized: localized)
        for field in try record.fields() {
            contents.decode(field: field)
        }
        contents.closeOpenResponse()
        editorID = contents.editorID
        flags = contents.flags
        legacyDialogueTab = contents.legacyDialogueTab
        resetHours = contents.resetHours
        previousTopic = contents.previousTopic
        previousInfo = contents.previousInfo
        favorLevel = contents.favorLevel
        topicLinks = contents.topicLinks
        sharedInfo = contents.sharedInfo
        responses = contents.responses
        conditions = contents.conditions
        prompt = contents.prompt
        speaker = contents.speaker
        walkAwayTopic = contents.walkAwayTopic
        audioOutputOverride = contents.audioOutputOverride
        script = contents.script
        skipped = contents.tally
    }
}

nonisolated extension TopicInfo {
    /// A copy with the FormIDs it links through passed through `translate`. The
    /// conditions stay as written; the evaluator translates them.
    public func renumbered(_ translate: (FormID) -> FormID) -> TopicInfo {
        var copy = self
        copy.formID = translate(formID)
        copy.previousTopic = previousTopic.map(translate)
        copy.previousInfo = previousInfo.map(translate)
        copy.topicLinks = topicLinks.map(translate)
        copy.sharedInfo = sharedInfo.map(translate)
        copy.speaker = speaker.map(translate)
        copy.walkAwayTopic = walkAwayTopic.map(translate)
        copy.audioOutputOverride = audioOutputOverride.map(translate)
        return copy
    }
}
