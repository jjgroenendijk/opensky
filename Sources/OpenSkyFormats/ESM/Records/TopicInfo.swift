// INFO, one selectable dialogue response set under a DIAL topic. TRDT opens a
// response run; NAM1/NAM2/NAM3 and the idle-animation links extend that run
// until the next TRDT. Conditions and record-level links remain outside it.
//
// References:
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/INFO
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas, `wbRecord(INFO, ...)`.

import Foundation

nonisolated package struct TopicInfo {
    package struct Flags: OptionSet, Equatable {
        package let rawValue: UInt16

        package init(rawValue: UInt16) {
            self.rawValue = rawValue
        }

        package static let goodbye = Flags(rawValue: 1 << 0)
        package static let random = Flags(rawValue: 1 << 1)
        package static let sayOnce = Flags(rawValue: 1 << 2)
        package static let requiresPlayerActivation = Flags(rawValue: 1 << 3)
        package static let infoRefusal = Flags(rawValue: 1 << 4)
        package static let randomEnd = Flags(rawValue: 1 << 5)
        package static let invisibleContinue = Flags(rawValue: 1 << 6)
        package static let walkAway = Flags(rawValue: 1 << 7)
        package static let walkAwayInvisibleInMenu = Flags(rawValue: 1 << 8)
        package static let forceSubtitle = Flags(rawValue: 1 << 9)
        package static let canMoveWhileGreeting = Flags(rawValue: 1 << 10)
        package static let noLipFile = Flags(rawValue: 1 << 11)
        package static let requiresPostProcessing = Flags(rawValue: 1 << 12)
        package static let hasAudioOutputOverride = Flags(rawValue: 1 << 13)
        package static let spendsFavorPoints = Flags(rawValue: 1 << 14)
    }

    package enum FavorLevel: Equatable {
        case none
        case small
        case medium
        case large
        case unknown(UInt8)

        package init(rawValue: UInt8) {
            switch rawValue {
            case 0: self = .none
            case 1: self = .small
            case 2: self = .medium
            case 3: self = .large
            default: self = .unknown(rawValue)
            }
        }
    }

    package struct Response: Equatable {
        package enum Emotion: Equatable {
            case neutral
            case anger
            case disgust
            case fear
            case sad
            case happy
            case surprise
            case puzzled
            case unknown(UInt32)

            package init(rawValue: UInt32) {
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

        package let emotion: Emotion
        package let emotionValue: UInt32
        package let number: UInt8
        package let sound: FormID?
        package let usesEmotionAnimation: Bool
        package var text: LString?
        package var scriptNotes: String?
        package var edits: String?
        package var speakerIdle: FormID?
        package var listenerIdle: FormID?
    }

    package let formID: FormID
    package let editorID: String?
    package let flags: Flags
    /// DATA only, absent from ENAM-era records.
    package let legacyDialogueTab: UInt16?
    /// DATA days or ENAM's scaled day fraction, normalized to hours.
    package let resetHours: Float
    package let previousTopic: FormID?
    package let previousInfo: FormID?
    package let favorLevel: FavorLevel
    package let topicLinks: [FormID]
    package let sharedInfo: FormID?
    package let responses: [Response]
    package let conditions: ConditionList
    package let prompt: LString?
    package let speaker: FormID?
    package let walkAwayTopic: FormID?
    package let audioOutputOverride: FormID?
    /// VMAD's script list, including the decoded INFO fragment tail.
    package let script: ScriptData
    package let skipped: DialogueTally

    /// Result-script fragments, from the VMAD tail rather than from a field of
    /// their own. Empty when the response carries no result script, and also
    /// when its fragment tail failed to decode (`script.skipped` records that).
    package var fragments: [TopicInfoFragment] {
        script.infoFragments?.fragments ?? []
    }

    /// The generated result script, "TIF_<editorID>_<formID>" by convention, or
    /// nil when the response carries no fragment at all.
    package var fragmentScriptName: String? {
        guard
            let section = script.infoFragments, !section.isEmpty,
            !section.fileName.isEmpty
        else {
            return nil
        }
        return section.fileName
    }

    package init(record: ESMRecord, localized: Bool = false) throws {
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
