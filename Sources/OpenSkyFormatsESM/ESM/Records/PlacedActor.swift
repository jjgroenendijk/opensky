// ACHR placed actor: one NPC_ base at a world position, shaped like REFR.
// Layout and sources: docs/formats/actors.md.

import Foundation
import OpenSkyFormatsCore
import simd

nonisolated public struct PlacedActor: Sendable {
    public let formID: FormID
    /// NAME — the NPC_ base actor this reference places.
    public let base: FormID
    public let placement: PlacedReference.Placement
    /// XSCL — uniform scale, defaulting to 1 when the field is absent.
    public let scale: Float
    /// Record-header flag 0x800 (UESP): the actor stays hidden until a quest
    /// or script enables it, so the renderer skips it.
    public let isInitiallyDisabled: Bool
    /// VMAD — Papyrus scripts attached directly to this placed actor.
    public let scriptData: ScriptData

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
                _ = try scriptData.decode(field: field)
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
    }
}
