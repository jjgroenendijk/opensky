// CLFM color form and EYES eye texture. Hair colors and head parts link a
// CLFM; a race lists its playable eyes. Layout and sources: docs/formats/head-parts.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct ColorForm: Equatable, Sendable {
    public let formID: FormID
    public let editorID: String?
    public let name: LString?
    /// CNAM red, green, blue, and the unused fourth byte.
    public let color: SIMD4<UInt8>?
    /// FNAM.
    public let isPlayable: Bool
    /// Record-header flag 0x04.
    public let isNonPlayable: Bool
    public let skipped: FieldTally

    public init(record: ESMRecord, localized: Bool) throws {
        var fields = try RecordFields(record: record, type: "CLFM", localized: localized)
        formID = fields.formID
        editorID = fields.editorID()
        name = fields.lstring("FULL")
        color = fields.read("CNAM") {
            try SIMD4($0.readUInt8(), $0.readUInt8(), $0.readUInt8(), $0.readUInt8())
        }
        isPlayable = (fields.uint32("FNAM") ?? 0) != 0
        isNonPlayable = record.flags.rawValue & 0x04 != 0
        skipped = fields.finish()
    }
}

nonisolated public struct Eyes: Equatable, Sendable {
    public let formID: FormID
    public let editorID: String?
    public let name: LString?
    /// ICON, relative to `Data/textures`.
    public let texturePath: String?
    /// DATA: 0x01 playable, 0x02 not male, 0x04 not female.
    public let flags: UInt8
    public let skipped: FieldTally

    public var isPlayable: Bool {
        flags & 0x01 != 0
    }

    public init(record: ESMRecord, localized: Bool) throws {
        var fields = try RecordFields(record: record, type: "EYES", localized: localized)
        formID = fields.formID
        editorID = fields.editorID()
        name = fields.lstring("FULL")
        texturePath = fields.zstring("ICON")
        flags = fields.uint8("DATA") ?? 0
        skipped = fields.finish()
    }
}
