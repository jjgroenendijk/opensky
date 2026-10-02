// ADDN addon node and RFCT visual effect: the particle systems and effect art a
// model attaches by node index or a spell plays. Layout and sources:
// docs/formats/visual-effects.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct AddonNode: Equatable, Sendable {
    public let formID: FormID
    public let editorID: String?
    public let bounds: ObjectBounds?
    public let model: ModelData?
    /// DATA, the index a mesh's addon-node extra data names.
    public let nodeIndex: UInt32?
    /// SNAM, a SNDR.
    public let sound: FormID?
    /// DNAM first half.
    public let masterParticleSystemCap: UInt16?
    /// DNAM second half: 1 master particle system, 3 always loaded.
    public let flags: UInt16?
    public let skipped: FieldTally

    public init(record: ESMRecord) throws {
        var fields = try RecordFields(record: record, type: "ADDN")
        formID = fields.formID
        editorID = fields.editorID()
        bounds = fields.bounds()
        model = fields.model()
        nodeIndex = fields.uint32("DATA")
        sound = fields.formID("SNAM")
        let data = fields.read("DNAM") { try ($0.readUInt16(), $0.readUInt16()) }
        masterParticleSystemCap = data?.0
        flags = data?.1
        skipped = fields.finish()
    }
}

nonisolated public struct VisualEffect: Equatable, Sendable {
    public let formID: FormID
    public let editorID: String?
    /// DATA: an ARTO.
    public let effectArt: FormID?
    /// DATA: an EFSH.
    public let shader: FormID?
    /// DATA: 0x01 rotate to face target, 0x02 attach to camera, 0x04 inherit rotation.
    public let flags: UInt32
    public let skipped: FieldTally

    public init(record: ESMRecord) throws {
        var fields = try RecordFields(record: record, type: "RFCT")
        formID = fields.formID
        editorID = fields.editorID()
        let data = fields.read("DATA") { try ($0.readFormID(), $0.readFormID(), $0.readUInt32()) }
        effectArt = data?.0.nonNull
        shader = data?.1.nonNull
        flags = data?.2 ?? 0
        skipped = fields.finish()
    }
}
