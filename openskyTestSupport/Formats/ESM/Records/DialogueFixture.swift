// Synthetic DIAL/INFO/VTYP records and DIAL child groups, every byte built in
// code from the UESP and xEdit layouts. Never extracted game data.

import Foundation
@testable import opensky

enum DialogueFixture {
    static func parse(_ bytes: Data) throws -> ESMRecord {
        let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
        guard case let .record(record)? = children.first else {
            throw ESMError.malformed("fixture did not produce a record")
        }
        return record
    }

    static func topicRecord(
        formID: UInt32 = 0x100,
        fields: Data,
        compressed: Bool = false
    ) -> Data {
        if compressed {
            return ESMFixture.compressedRecord("DIAL", formID: formID, fieldData: fields)
        }
        return ESMFixture.record("DIAL", formID: formID, data: fields)
    }

    static func infoRecord(
        formID: UInt32 = 0x200,
        fields: Data,
        compressed: Bool = false
    ) -> Data {
        if compressed {
            return ESMFixture.compressedRecord("INFO", formID: formID, fieldData: fields)
        }
        return ESMFixture.record("INFO", formID: formID, data: fields)
    }

    static func voiceRecord(formID: UInt32 = 0x300, fields: Data) -> Data {
        ESMFixture.record("VTYP", formID: formID, data: fields)
    }

    static func topic(_ fields: Data, localized: Bool = false) throws -> DialogueTopic {
        try DialogueTopic(record: parse(topicRecord(fields: fields)), localized: localized)
    }

    static func info(_ fields: Data, localized: Bool = false) throws -> TopicInfo {
        try TopicInfo(record: parse(infoRecord(fields: fields)), localized: localized)
    }

    static func voice(_ fields: Data) throws -> VoiceType {
        try VoiceType(record: parse(voiceRecord(fields: fields)))
    }

    static func plugin(
        dialogueChildren: Data = Data(),
        voiceRecords: Data = Data(),
        localized: Bool = false
    ) -> Data {
        var data = ESMFixture.tes4(flags: localized ? 0x81 : 1)
        if !dialogueChildren.isEmpty {
            data += ESMFixture.topGroup("DIAL", contents: dialogueChildren)
        }
        if !voiceRecords.isEmpty {
            data += ESMFixture.topGroup("VTYP", contents: voiceRecords)
        }
        return data
    }

    /// Plugin name every synthetic dialogue store is keyed under, so an INFO's
    /// `ReferenceKey` matches the one a save fixture writes.
    static let pluginName = "opensky-test.esm"

    static func store(
        dialogueChildren: Data = Data(),
        voiceRecords: Data = Data(),
        localized: Bool = false
    ) throws -> DialogueStore {
        let bytes = plugin(
            dialogueChildren: dialogueChildren,
            voiceRecords: voiceRecords,
            localized: localized
        )
        return try DialogueStore(file: ESMFile(data: bytes), pluginName: pluginName)
    }

    static func topicChildren(parent: UInt32, infos: Data) -> Data {
        ESMFixture.childGroup(parent: parent, groupType: 7, contents: infos)
    }

    static func editorID(_ value: String) -> Data {
        ESMFixture.field("EDID", ESMFixture.zstring(value))
    }

    static func inlineText(_ type: String, _ value: String) -> Data {
        ESMFixture.field(type, ESMFixture.zstring(value))
    }

    static func localizedText(_ type: String, id: UInt32) -> Data {
        word(type, id)
    }

    static func word(_ type: String, _ value: UInt32) -> Data {
        var data = Data()
        data.appendUInt32(value)
        return ESMFixture.field(type, data)
    }

    /// DIAL DATA: uint8 repeat behavior, uint8 category, uint16 legacy subtype.
    static func topicData(
        repeatsAll: Bool = false,
        category: UInt8 = 0,
        legacySubtype: UInt16 = 0
    ) -> Data {
        var data = Data([repeatsAll ? 1 : 0, category])
        data.appendUInt16(legacySubtype)
        return ESMFixture.field("DATA", data)
    }

    static func priority(_ value: Float) -> Data {
        var data = Data()
        data.appendUInt32(value.bitPattern)
        return ESMFixture.field("PNAM", data)
    }

    static func subtype(_ value: String) -> Data {
        ESMFixture.field("SNAM", Data(value.utf8))
    }

    /// INFO ENAM: uint16 flags, uint16 scaled reset interval.
    static func infoData(flags: UInt16 = 0, reset: UInt16 = 0) -> Data {
        var data = Data()
        data.appendUInt16(flags)
        data.appendUInt16(reset)
        return ESMFixture.field("ENAM", data)
    }

    /// INFO TRDT, 24 bytes.
    static func response(
        emotion: UInt32 = 0,
        emotionValue: UInt32 = 0,
        number: UInt8 = 1,
        sound: UInt32 = 0,
        usesEmotionAnimation: Bool = false
    ) -> Data {
        var data = Data()
        data.appendUInt32(emotion)
        data.appendUInt32(emotionValue)
        data.appendUInt32(0)
        data.append(contentsOf: [number, 0, 0, 0])
        data.appendUInt32(sound)
        data.append(contentsOf: [usesEmotionAnimation ? 1 : 0, 0, 0, 0])
        return ESMFixture.field("TRDT", data)
    }

    /// CTDA, 32 bytes: `function(parameter1) <operator> comparisonValue`.
    static func condition(
        functionIndex: UInt16 = 0,
        operatorBits: UInt8 = 0,
        flags: UInt8 = 0,
        comparisonValue: Float = 0,
        parameter1: UInt32 = 0,
        parameter2: UInt32 = 0,
        runOn: UInt32 = 0,
        parameter3: Int32 = -1
    ) -> Data {
        var data = Data([(operatorBits << 5) | (flags & 0x1F), 0, 0, 0])
        data.appendUInt32(comparisonValue.bitPattern)
        data.appendUInt16(functionIndex)
        data.appendUInt16(0) // padding
        data.appendUInt32(parameter1)
        data.appendUInt32(parameter2)
        data.appendUInt32(runOn)
        data.appendUInt32(0) // reference, only read under run-on 2
        data.appendUInt32(UInt32(bitPattern: parameter3))
        return ESMFixture.field("CTDA", data)
    }

    /// `GetIsID(base) == 1` on the subject, which is how a vanilla INFO names
    /// the NPC allowed to say it.
    static func isSpeaker(_ base: UInt32) -> Data {
        condition(functionIndex: 72, comparisonValue: 1, parameter1: base)
    }

    /// `GetQuestRunning(quest) == 1`, one of the quest gates a real INFO uses.
    static func questRunning(_ quest: UInt32) -> Data {
        condition(functionIndex: 56, comparisonValue: 1, parameter1: quest)
    }

    // MARK: - VMAD

    /// A VMAD field carrying a primary script list plus an INFO fragment tail.
    static func vmad(scripts: [VMADFixture.Script] = [], tail: Data) -> Data {
        ESMFixture.field("VMAD", VMADFixture.payload(scripts: scripts, tail: tail))
    }

    /// The INFO fragment tail: int8 bind version, uint8 flags, wstring file
    /// name, then one entry per set flag bit in begin-then-end order.
    ///
    /// - Parameter flags: written verbatim when supplied, so a test can build
    ///   the mismatched or undocumented byte the decoder has to refuse.
    static func infoFragmentTail(
        fileName: String,
        begin: String? = nil,
        end: String? = nil,
        bindVersion: Int8 = 2,
        flags: UInt8? = nil
    ) -> Data {
        var declared: UInt8 = 0
        if begin != nil {
            declared |= 1 << 0
        }
        if end != nil {
            declared |= 1 << 1
        }
        var data = Data([UInt8(bitPattern: bindVersion), flags ?? declared])
        data.appendDialogueString(fileName)
        for function in [begin, end].compactMap(\.self) {
            data.append(1) // always one in shipped data
            data.appendDialogueString(fileName)
            data.appendDialogueString(function)
        }
        return data
    }
}

extension Data {
    fileprivate mutating func appendDialogueString(_ value: String) {
        let bytes = Data(value.utf8)
        appendUInt16(UInt16(bytes.count))
        append(bytes)
    }
}
