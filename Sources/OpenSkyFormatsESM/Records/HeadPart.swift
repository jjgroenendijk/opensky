// HDPT head part: a face, hair, eyes, or other head mesh with its morph TRI
// files. NAM0 marks the next NAM1 path as race morph (0), expression (1), or
// chargen morph (2). Layout and sources: docs/formats/head-parts.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct HeadPart: Equatable, Sendable {
    nonisolated public enum MorphKind: UInt32, Equatable, Sendable {
        case race = 0
        case expression = 1
        case chargen = 2
    }

    nonisolated public struct MorphPath: Equatable, Sendable {
        public let kind: MorphKind
        public let path: String
    }

    /// PNAM. An unknown value keeps its number.
    nonisolated public enum PartType: Equatable, Hashable, Sendable {
        case misc
        case face
        case eyes
        case hair
        case facialHair
        case scar
        case eyebrows
        case unknown(UInt32)

        public init(rawValue: UInt32) {
            let known: [PartType] = [.misc, .face, .eyes, .hair, .facialHair, .scar, .eyebrows]
            self = rawValue < known.count ? known[Int(rawValue)] : .unknown(rawValue)
        }
    }

    /// DATA flag bits.
    public struct Flags: OptionSet, Equatable, Sendable {
        public let rawValue: UInt8

        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        public static let playable = Flags(rawValue: 0x01)
        public static let male = Flags(rawValue: 0x02)
        public static let female = Flags(rawValue: 0x04)
        public static let isExtraPart = Flags(rawValue: 0x08)
        public static let usesSolidTint = Flags(rawValue: 0x10)
    }

    public let formID: FormID
    public let editorID: String?
    public let name: LString?
    public let model: ModelData?
    public let flags: Flags
    public let partType: PartType?
    /// HNAM, other HDPT records that come with this one.
    public let extraParts: [FormID]
    public let morphPaths: [MorphPath]
    /// TNAM, a TXST.
    public let textureSet: FormID?
    /// CNAM, a CLFM.
    public let color: FormID?
    /// RNAM, a FLST of the races that may use the part.
    public let validRaces: FormID?
    public let skipped: FieldTally

    public var expressionMorphPath: String? {
        morphPaths.first { $0.kind == .expression }?.path
    }

    public init(record: ESMRecord, localized: Bool = false) throws {
        var fields = try RecordFields(record: record, type: "HDPT", localized: localized)
        formID = fields.formID
        editorID = fields.editorID()
        name = fields.lstring("FULL")
        model = fields.model()
        flags = Flags(rawValue: fields.uint8("DATA") ?? 0)
        partType = fields.uint32("PNAM").map(PartType.init(rawValue:))
        extraParts = fields.formIDs("HNAM")
        textureSet = fields.formID("TNAM")
        color = fields.formID("CNAM")
        validRaces = fields.formID("RNAM")
        morphPaths = Self.morphPaths(&fields)
        skipped = fields.finish()
    }

    private static func morphPaths(_ fields: inout RecordFields) -> [MorphPath] {
        var pendingKind: MorphKind?
        var paths: [MorphPath] = []
        for index in fields.fields.indices {
            switch fields.fields[index].type {
            case "NAM0":
                let raw = fields.read(at: index) { try $0.readUInt32() }
                pendingKind = raw.flatMap(MorphKind.init(rawValue:))
                if raw != nil, pendingKind == nil {
                    fields.note(.mismatch("HDPT NAM0 part type outside 0...2"))
                }
            case "NAM1":
                let path = fields.read(at: index) { try $0.readZString() }
                if let kind = pendingKind, let path {
                    paths.append(MorphPath(kind: kind, path: path))
                }
                pendingKind = nil
            default:
                continue
            }
        }
        return paths
    }
}
