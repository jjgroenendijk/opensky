// INFO, one selectable dialogue response set under a DIAL topic. TRDT opens a
// response run; NAM1/NAM2/NAM3 and the idle-animation links extend that run
// until the next TRDT. Conditions and record-level links remain outside it.
//
// References:
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/INFO
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas, `wbRecord(INFO, ...)`.

import Foundation

nonisolated struct TopicInfo {
    struct Flags: OptionSet, Equatable {
        let rawValue: UInt16

        static let goodbye = Flags(rawValue: 1 << 0)
        static let random = Flags(rawValue: 1 << 1)
        static let sayOnce = Flags(rawValue: 1 << 2)
        static let requiresPlayerActivation = Flags(rawValue: 1 << 3)
        static let infoRefusal = Flags(rawValue: 1 << 4)
        static let randomEnd = Flags(rawValue: 1 << 5)
        static let invisibleContinue = Flags(rawValue: 1 << 6)
        static let walkAway = Flags(rawValue: 1 << 7)
        static let walkAwayInvisibleInMenu = Flags(rawValue: 1 << 8)
        static let forceSubtitle = Flags(rawValue: 1 << 9)
        static let canMoveWhileGreeting = Flags(rawValue: 1 << 10)
        static let noLipFile = Flags(rawValue: 1 << 11)
        static let requiresPostProcessing = Flags(rawValue: 1 << 12)
        static let hasAudioOutputOverride = Flags(rawValue: 1 << 13)
        static let spendsFavorPoints = Flags(rawValue: 1 << 14)
    }

    enum FavorLevel: Equatable {
        case none
        case small
        case medium
        case large
        case unknown(UInt8)

        init(rawValue: UInt8) {
            switch rawValue {
            case 0: self = .none
            case 1: self = .small
            case 2: self = .medium
            case 3: self = .large
            default: self = .unknown(rawValue)
            }
        }
    }

    struct Response: Equatable {
        enum Emotion: Equatable {
            case neutral
            case anger
            case disgust
            case fear
            case sad
            case happy
            case surprise
            case puzzled
            case unknown(UInt32)

            init(rawValue: UInt32) {
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

        let emotion: Emotion
        let emotionValue: UInt32
        let number: UInt8
        let sound: FormID?
        let usesEmotionAnimation: Bool
        var text: LString?
        var scriptNotes: String?
        var edits: String?
        var speakerIdle: FormID?
        var listenerIdle: FormID?

        /// Dialogue response text is stored in the plugin's ILSTRINGS table.
        func resolvedText(using strings: LocalizedStrings) -> String? {
            strings.resolve(text, kind: .ilstrings)
        }
    }

    let formID: FormID
    let editorID: String?
    let flags: Flags
    /// DATA only, absent from ENAM-era records.
    let legacyDialogueTab: UInt16?
    /// DATA days or ENAM's scaled day fraction, normalized to hours.
    let resetHours: Float
    let previousTopic: FormID?
    let previousInfo: FormID?
    let favorLevel: FavorLevel
    let topicLinks: [FormID]
    let sharedInfo: FormID?
    let responses: [Response]
    let conditions: ConditionList
    let prompt: LString?
    let speaker: FormID?
    let walkAwayTopic: FormID?
    let audioOutputOverride: FormID?
    /// VMAD's script list. INFO's fragment tail remains skipped by ScriptData.
    let script: ScriptData
    let skipped: DialogueTally

    init(record: ESMRecord, localized: Bool = false) throws {
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
