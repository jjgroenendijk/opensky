// SNDR sound descriptors bind one or more audio tracks to playback settings.
// SOUN sound markers provide the legacy record identity used by game references
// and point at an SNDR through SDSC.

import Foundation

nonisolated struct SoundDescriptor {
    enum Looping: Equatable {
        case none
        case loop
        case envelopeFast
        case envelopeSlow
        case unknown(UInt8)
    }

    struct Parameters: Equatable {
        let frequencyShiftPercent: Int
        let frequencyVariancePercent: Int
        let priority: Int
        let decibelVariance: Int
        let staticAttenuationDecibels: Float
    }

    let formID: FormID
    let editorID: String?
    let descriptorType: UInt32?
    let category: FormID?
    let alternateFor: FormID?
    let tracks: [String]
    let outputModel: FormID?
    let looping: Looping?
    let parameters: Parameters?

    init(record: ESMRecord) throws {
        guard record.type == "SNDR" else {
            throw ESMError.malformed("expected SNDR record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var editorID: String?
        var descriptorType: UInt32?
        var category: FormID?
        var alternateFor: FormID?
        var tracks: [String] = []
        var outputModel: FormID?
        var looping: Looping?
        var parameters: Parameters?

        // Field layouts:
        // https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/SNDR
        // https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas
        for field in try record.fields() {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "CNAM":
                descriptorType = try Self.readOptionalUInt32(&reader, size: field.data.count)
            case "GNAM":
                category = try Self.readOptionalFormID(&reader, size: field.data.count)
            case "SNAM":
                alternateFor = try Self.readOptionalFormID(&reader, size: field.data.count)
            case "ANAM":
                try tracks.append(reader.readZString())
            case "ONAM":
                outputModel = try Self.readOptionalFormID(&reader, size: field.data.count)
            case "LNAM":
                looping = try Self.readLooping(&reader, size: field.data.count)
            case "BNAM":
                parameters = try Self.readParameters(&reader, size: field.data.count)
            default:
                // Conditions and older-version fields do not affect playback here.
                break
            }
        }

        self.editorID = editorID
        self.descriptorType = descriptorType
        self.category = category
        self.alternateFor = alternateFor
        self.tracks = tracks
        self.outputModel = outputModel
        self.looping = looping
        self.parameters = parameters
    }

    private static func readOptionalUInt32(
        _ reader: inout BinaryReader,
        size: Int
    ) throws -> UInt32? {
        guard size == 4 else { return nil }
        return try reader.readUInt32()
    }

    private static func readOptionalFormID(
        _ reader: inout BinaryReader,
        size: Int
    ) throws -> FormID? {
        guard size == 4 else { return nil }
        let formID = try FormID(reader.readUInt32())
        return formID.isNull ? nil : formID
    }

    private static func readLooping(
        _ reader: inout BinaryReader,
        size: Int
    ) throws -> Looping? {
        guard size == 4 else { return nil }
        _ = try reader.readUInt8()
        let selector = try reader.readUInt8()
        switch selector {
        case 0:
            return Looping.none
        case 8:
            return .loop
        case 16:
            return .envelopeFast
        case 32:
            return .envelopeSlow
        default:
            return .unknown(selector)
        }
    }

    private static func readParameters(
        _ reader: inout BinaryReader,
        size: Int
    ) throws -> Parameters? {
        guard size == 6 else { return nil }
        let frequencyShift = try Int(Int8(bitPattern: reader.readUInt8()))
        let frequencyVariance = try Int(Int8(bitPattern: reader.readUInt8()))
        let priority = try Int(reader.readUInt8())
        let decibelVariance = try Int(reader.readUInt8())
        let staticAttenuation = try Float(reader.readUInt16()) / 100
        return Parameters(
            frequencyShiftPercent: frequencyShift,
            frequencyVariancePercent: frequencyVariance,
            priority: priority,
            decibelVariance: decibelVariance,
            staticAttenuationDecibels: staticAttenuation
        )
    }
}

nonisolated struct SoundMarker {
    let formID: FormID
    let editorID: String?
    let descriptor: FormID?

    init(record: ESMRecord) throws {
        guard record.type == "SOUN" else {
            throw ESMError.malformed("expected SOUN record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var editorID: String?
        var descriptor: FormID?
        // Field layouts:
        // https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/SOUN
        // https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas
        for field in try record.fields() {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "SDSC":
                guard field.data.count == 4 else { continue }
                let formID = try FormID(reader.readUInt32())
                descriptor = formID.isNull ? nil : formID
            default:
                // FNAM and SNDD are obsolete, unused SOUN fields.
                break
            }
        }
        self.editorID = editorID
        self.descriptor = descriptor
    }
}
