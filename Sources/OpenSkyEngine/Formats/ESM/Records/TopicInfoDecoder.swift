// INFO's record-level state machine. Response field handling is split into
// TopicInfoResponseDecoder.swift to keep the strict function and file caps.

import Foundation

nonisolated extension TopicInfo {
    struct Contents {
        let localized: Bool
        var editorID: String?
        var flags = Flags()
        var legacyDialogueTab: UInt16?
        var resetHours: Float = 0
        var previousTopic: FormID?
        var previousInfo: FormID?
        var favorLevel = FavorLevel.none
        var topicLinks: [FormID] = []
        var sharedInfo: FormID?
        var responses: [Response] = []
        var conditions = ConditionList()
        var prompt: LString?
        var speaker: FormID?
        var walkAwayTopic: FormID?
        var audioOutputOverride: FormID?
        var script = ScriptData(ownerType: "INFO")
        var tally = DialogueTally()
        var openResponse: Response?

        mutating func decode(field: ESMField) {
            do {
                if try decodeKnown(field: field) {
                    return
                }
                tally.note(.unknownField(field.type))
            } catch {
                tally.note(.malformedField(field.type))
            }
        }

        mutating func closeOpenResponse() {
            if let openResponse {
                responses.append(openResponse)
                self.openResponse = nil
            }
        }

        private mutating func decodeKnown(field: ESMField) throws -> Bool {
            if field.type == "TRDT" {
                try beginResponse(field)
                return true
            }
            if isResponseField(field.type) {
                try decodeResponseField(field)
                return true
            }
            if try decodeHeader(field) {
                return true
            }
            if try decodeReference(field) {
                return true
            }
            return try decodeCondition(field)
        }

        private mutating func decodeHeader(_ field: ESMField) throws -> Bool {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID": editorID = try reader.readZString()
            case "VMAD": try script.decode(field: field)
            case "DATA": try decodeLegacyData(field)
            case "ENAM": try decodeCurrentData(field)
            case "CNAM": favorLevel = try FavorLevel(rawValue: reader.readUInt8())
            case "RNAM": prompt = try LString(field: field, localized: localized)
            default: return false
            }
            return true
        }

        private mutating func decodeReference(_ field: ESMField) throws -> Bool {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "TPIC": previousTopic = try Self.readReference(&reader)
            case "PNAM": previousInfo = try Self.readReference(&reader)
            case "TCLT":
                if let value = try Self.readReference(&reader) {
                    topicLinks.append(value)
                }
            case "DNAM": sharedInfo = try Self.readReference(&reader)
            case "ANAM": speaker = try Self.readReference(&reader)
            case "TWAT": walkAwayTopic = try Self.readReference(&reader)
            case "ONAM": audioOutputOverride = try Self.readReference(&reader)
            default: return false
            }
            return true
        }

        private mutating func decodeCondition(_ field: ESMField) throws -> Bool {
            switch field.type {
            case "CTDA" where field.data.count != 32,
                 "CITC" where field.data.count != 4:
                tally.note(.malformedField(field.type))
                return true
            default:
                return try conditions.decode(field: field)
            }
        }

        /// DATA: uint16 dialogue tab, uint16 flags, float reset days.
        private mutating func decodeLegacyData(_ field: ESMField) throws {
            guard field.data.count >= 8 else { throw Self.short(field, expected: 8) }
            var reader = BinaryReader(field.data)
            legacyDialogueTab = try reader.readUInt16()
            flags = try Flags(rawValue: reader.readUInt16())
            resetHours = try reader.readFloat32() * 24
        }

        /// ENAM: uint16 flags, uint16 scaled 0...24-hour reset interval.
        private mutating func decodeCurrentData(_ field: ESMField) throws {
            guard field.data.count >= 4 else { throw Self.short(field, expected: 4) }
            var reader = BinaryReader(field.data)
            flags = try Flags(rawValue: reader.readUInt16())
            let scaled = try reader.readUInt16()
            resetHours = Float(scaled) * 24 / Float(UInt16.max)
        }

        static func readReference(_ reader: inout BinaryReader) throws -> FormID? {
            let value = try FormID(reader.readUInt32())
            return value.isNull ? nil : value
        }

        private static func short(_ field: ESMField, expected: Int) -> BinaryReaderError {
            BinaryReaderError.outOfBounds(
                offset: 0,
                count: expected,
                available: field.data.count
            )
        }
    }
}
