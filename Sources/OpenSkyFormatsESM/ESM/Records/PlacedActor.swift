// ACHR placed actor: one NPC_ base at a world position, shaped like REFR.
// Layout and sources: docs/formats/actors.md.

import Foundation
import OpenSkyFormatsCore
import simd

nonisolated public struct PlacedActor: Sendable {
    public internal(set) var formID: FormID
    /// NAME — the NPC_ base actor this reference places.
    public internal(set) var base: FormID
    public let placement: PlacedReference.Placement
    /// XSCL — uniform scale, defaulting to 1 when the field is absent.
    public let scale: Float
    /// Record-header flag 0x800 (UESP): the actor stays hidden until a quest
    /// or script enables it, so the renderer skips it.
    public let isInitiallyDisabled: Bool
    /// VMAD — Papyrus scripts attached directly to this placed actor.
    public internal(set) var scriptData: ScriptData
    /// XESP.
    public internal(set) var enableParent: EnableParent?
    public internal(set) var details: PlacedReferenceDetails
    /// Fields this decode does not read.
    public let skipped: FieldTally

    public init(
        copying actor: PlacedActor,
        placement: PlacedReference.Placement,
        scale: Float
    ) {
        formID = actor.formID
        base = actor.base
        self.placement = placement
        self.scale = scale
        isInitiallyDisabled = actor.isInitiallyDisabled
        scriptData = actor.scriptData
        enableParent = actor.enableParent
        details = actor.details
        skipped = actor.skipped
    }

    public init(record: ESMRecord) throws {
        guard record.type == "ACHR" else {
            throw ESMError.malformed("expected ACHR record, got \(record.type)")
        }
        formID = FormID(record.formID)
        isInitiallyDisabled = record.isInitiallyDisabled

        var base: FormID?
        var placement: PlacedReference.Placement?
        var scale: Float = 1
        var scriptData = ScriptData(ownerType: record.type)
        var extras = PlacedReferenceExtras()
        var unread: [ESMField] = []
        for field in try record.fields() {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "NAME":
                base = try FormID(reader.readUInt32())
            case "DATA":
                placement = try PlacedReference.Placement(
                    position: SIMD3(
                        Float(bitPattern: reader.readUInt32()),
                        Float(bitPattern: reader.readUInt32()),
                        Float(bitPattern: reader.readUInt32())
                    ),
                    rotation: SIMD3(
                        Float(bitPattern: reader.readUInt32()),
                        Float(bitPattern: reader.readUInt32()),
                        Float(bitPattern: reader.readUInt32())
                    )
                )
            case "XSCL":
                scale = try Float(bitPattern: reader.readUInt32())
            default:
                if !extras.decode(field), try !scriptData.decode(field: field) {
                    unread.append(field)
                }
            }
        }
        guard let base else {
            throw ESMError.malformed("ACHR \(formID) has no NAME field")
        }
        guard let placement else {
            throw ESMError.malformed("ACHR \(formID) has no DATA field")
        }
        self.base = base
        self.placement = placement
        self.scale = scale
        self.scriptData = scriptData
        enableParent = extras.enableParent
        let (details, detailTally) = PlacedReferenceDetails.decode(unread)
        self.details = details
        var tally = extras.tally
        tally.merge(detailTally)
        skipped = tally
    }
}
