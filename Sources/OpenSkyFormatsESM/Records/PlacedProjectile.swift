// PHZD placed hazard and PGRE placed projectile: a HAZD or PROJ base at a world
// position. They sit in cell children next to REFR and ACHR.
// Layout and sources: docs/formats/placed-references.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct PlacedProjectile: Sendable {
    public static let recordTypes: Set<FourCC> = ["PHZD", "PGRE"]

    public let formID: FormID
    public let recordType: FourCC
    public let editorID: String?
    /// NAME: a HAZD for PHZD, a PROJ for PGRE.
    public let base: FormID
    public let placement: PlacedReference.Placement
    /// XSCL, 1 when absent.
    public let scale: Float
    public let isInitiallyDisabled: Bool
    public let enableParent: EnableParent?
    /// XOWN.
    public let owner: FormID?
    public let encounterZone: FormID?
    public let linkedReferences: [PlacedReference.LinkedReference]
    public let scriptData: ScriptData
    public let skipped: FieldTally

    public init(record: ESMRecord) throws {
        var fields = try RecordFields(record: record, types: Self.recordTypes)
        guard let base = fields.formID("NAME") else {
            throw ESMError.malformed("\(record.type) \(fields.formID) has no NAME field")
        }
        guard let placement = fields.read("DATA", { try PlacedReference.Placement(&$0) }) else {
            throw ESMError.malformed("\(record.type) \(fields.formID) has no DATA field")
        }
        formID = fields.formID
        recordType = record.type
        editorID = fields.editorID()
        self.base = base
        self.placement = placement
        scale = fields.float("XSCL") ?? 1
        isInitiallyDisabled = record.isInitiallyDisabled
        enableParent = fields.read("XESP") { try EnableParent(&$0) }
        owner = fields.formID("XOWN")
        encounterZone = fields.formID("XEZN")
        linkedReferences = fields.readAll("XLKR") { try PlacedReference.LinkedReference(&$0) }
        var scriptData = ScriptData(ownerType: record.type)
        for index in fields.fields.indices where fields.fields[index].type == "VMAD" {
            let field = fields.fields[index]
            _ = fields.read(at: index) { _ in try scriptData.decode(field: field) }
        }
        self.scriptData = scriptData
        skipped = fields.finish()
    }
}

nonisolated extension PlacedReference.Placement {
    /// DATA: position xyz, then rotation xyz in radians.
    init(_ reader: inout BinaryReader) throws {
        try self.init(position: reader.readFloat3(), rotation: reader.readFloat3())
    }
}

nonisolated extension PlacedReference.LinkedReference {
    /// XLKR: keyword then reference, or a lone 4-byte reference.
    init(_ reader: inout BinaryReader) throws {
        let first = try reader.readFormID()
        if reader.bytesRemaining >= 4 {
            try self.init(keyword: first.nonNull, ref: reader.readFormID())
        } else {
            self.init(keyword: nil, ref: first)
        }
    }
}
