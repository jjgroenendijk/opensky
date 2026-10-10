// SNDR sound descriptors bind one or more audio tracks to playback settings.
// SOUN sound markers provide the legacy record identity used by game references
// and point at an SNDR through SDSC.

import Foundation
import OpenSkyFormatsCore

/// SNCT sound-category node. Categories form a parent hierarchy; the records
/// flagged `shouldAppearOnMenu` are the user-facing mixer categories.
nonisolated public struct SoundCategory: Sendable {
    public struct Flags: OptionSet, Equatable, Sendable {
        public let rawValue: UInt32

        public init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        public static let muteWhenSubmerged = Flags(rawValue: 1 << 0)
        public static let shouldAppearOnMenu = Flags(rawValue: 1 << 1)
    }

    public let formID: FormID
    public let editorID: String?
    public let name: LString?
    public let flags: Flags
    public let parent: FormID?
    public let staticVolumeMultiplier: Float?
    public let defaultMenuValue: Float?
    public let skipped: FieldTally

    public init(record: ESMRecord, localized: Bool) throws {
        guard record.type == "SNCT" else {
            throw ESMError.malformed("expected SNCT record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var editorID: String?
        var name: LString?
        var flags: Flags = []
        var parent: FormID?
        var staticVolumeMultiplier: Float?
        var defaultMenuValue: Float?

        // Field layouts:
        // https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/SNCT
        // https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas
        var skipped = FieldTally()
        for field in try record.fields() {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "FULL":
                name = try LString(field: field, localized: localized)
            case "FNAM":
                guard field.data.count == 4 else { continue }
                flags = try Flags(rawValue: reader.readUInt32())
            case "PNAM":
                guard field.data.count == 4 else { continue }
                let value = try FormID(reader.readUInt32())
                parent = value.isNull ? nil : value
            case "VNAM":
                staticVolumeMultiplier = try Self.readVolume(&reader, size: field.data.count)
            case "UNAM":
                defaultMenuValue = try Self.readVolume(&reader, size: field.data.count)
            default:
                skipped.note(.unknownField(field.type))
            }
        }
        self.skipped = skipped

        self.editorID = editorID
        self.name = name
        self.flags = flags
        self.parent = parent
        self.staticVolumeMultiplier = staticVolumeMultiplier
        self.defaultMenuValue = defaultMenuValue
    }

    private static func readVolume(
        _ reader: inout BinaryReader,
        size: Int
    ) throws -> Float? {
        guard size == 2 else { return nil }
        return try Float(reader.readUInt16()) / Float(UInt16.max)
    }
}

nonisolated public struct SoundDescriptor: Sendable {
    public enum Looping: Equatable, Sendable {
        case none
        case loop
        case envelopeFast
        case envelopeSlow
        case unknown(UInt8)
    }

    public struct Parameters: Equatable, Sendable {
        public let frequencyShiftPercent: Int
        public let frequencyVariancePercent: Int
        public let priority: Int
        public let decibelVariance: Int
        public let staticAttenuationDecibels: Float
    }

    public let formID: FormID
    public let editorID: String?
    public let descriptorType: UInt32?
    public let category: FormID?
    public let alternateFor: FormID?
    public let tracks: [String]
    public let outputModel: FormID?
    public let looping: Looping?
    public let parameters: Parameters?
    /// CTDA run that gates playback.
    public let conditions: [Condition]
    /// FNAM — flags written before form version 35; bit 4 is loop.
    public let legacyFlags: UInt32?
    public let skipped: FieldTally

    public init(record: ESMRecord) throws {
        guard record.type == "SNDR" else {
            throw ESMError.malformed("expected SNDR record, got \(record.type)")
        }
        var rest = try RecordFields(record: record, type: "SNDR")
        let recordID = rest.formID
        formID = recordID

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
        try rest.readEach { field in
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
                return false
            }
            return true
        }
        conditions = rest.conditions()
        legacyFlags = rest.uint32("FNAM")
        skipped = rest.finish()

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

nonisolated public struct SoundMarker: Sendable {
    public let formID: FormID
    public let editorID: String?
    public let descriptor: FormID?
    public let bounds: ObjectBounds?
    /// FNAM and SNDD: leftovers xEdit marks unused, kept raw.
    public let legacyFNAM: Data?
    public let legacySNDD: Data?
    public let skipped: FieldTally

    /// Memberwise init for synthesized markers (e.g. when a SNDR FormID was
    /// stored directly on a DOOR/ACTI/CONT and the runtime resolves it
    /// without an actual SOUN record in the plugin).
    public init(formID: FormID, editorID: String?, descriptor: FormID?) {
        self.formID = formID
        self.editorID = editorID
        self.descriptor = descriptor
        bounds = nil
        legacyFNAM = nil
        legacySNDD = nil
        skipped = FieldTally()
    }

    public init(record: ESMRecord) throws {
        guard record.type == "SOUN" else {
            throw ESMError.malformed("expected SOUN record, got \(record.type)")
        }
        var rest = try RecordFields(record: record, type: "SOUN")
        let recordID = rest.formID
        formID = recordID

        var editorID: String?
        var descriptor: FormID?
        // Field layouts:
        // https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/SOUN
        // https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas
        try rest.readEach { field in
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "SDSC":
                guard field.data.count == 4 else { return true }
                let formID = try FormID(reader.readUInt32())
                descriptor = formID.isNull ? nil : formID
            default:
                return false
            }
            return true
        }
        bounds = rest.bounds()
        legacyFNAM = rest.bytes("FNAM")
        legacySNDD = rest.bytes("SNDD")
        skipped = rest.finish()
        self.editorID = editorID
        self.descriptor = descriptor
    }
}
