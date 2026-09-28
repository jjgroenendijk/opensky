// INFO response-run handling. TRDT's 24-byte layout comes from UESP INFO and
// xEdit `wbStruct(TRDT, 'Response Data', ...)` at dev-4.1.6 line 7871.

import Foundation

nonisolated extension TopicInfo.Contents {
    func isResponseField(_ type: FourCC) -> Bool {
        switch type {
        case "NAM1", "NAM2", "NAM3", "SNAM", "LNAM": true
        default: false
        }
    }

    mutating func beginResponse(_ field: ESMField) throws {
        closeOpenResponse()
        guard field.data.count >= 24 else {
            throw BinaryReaderError.outOfBounds(
                offset: 0,
                count: 24,
                available: field.data.count
            )
        }
        var reader = BinaryReader(field.data)
        let emotion = try TopicInfo.Response.Emotion(rawValue: reader.readUInt32())
        let emotionValue = try reader.readUInt32()
        reader.skip(4) // unused
        let number = try reader.readUInt8()
        reader.skip(3) // unused
        let soundValue = try FormID(reader.readUInt32())
        let usesEmotionAnimation = try reader.readUInt8() != 0
        openResponse = TopicInfo.Response(
            emotion: emotion,
            emotionValue: emotionValue,
            number: number,
            sound: soundValue.isNull ? nil : soundValue,
            usesEmotionAnimation: usesEmotionAnimation
        )
    }

    mutating func decodeResponseField(_ field: ESMField) throws {
        guard var response = openResponse else {
            tally.note(.orphanResponseField(field.type))
            return
        }
        var reader = BinaryReader(field.data)
        switch field.type {
        case "NAM1": response.text = try LString(field: field, localized: localized)
        case "NAM2": response.scriptNotes = try reader.readZString()
        case "NAM3": response.edits = try reader.readZString()
        case "SNAM": response.speakerIdle = try Self.readReference(&reader)
        case "LNAM": response.listenerIdle = try Self.readReference(&reader)
        default: return
        }
        openResponse = response
    }
}
