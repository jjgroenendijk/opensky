// EQUP equip slot, the target of every ETYP link. A slot names parent slots
// and says whether it takes all of them (BothHands) or one (EitherHand).
// `EquipSlotHands` turns that graph into `HandSlots`. Every PNAM appends.
// Layout and vanilla slots: docs/formats/shouts-equip-slots.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct EquipSlot: Equatable, Sendable {
    public let formID: FormID
    public let editorID: String?
    /// PNAM — the slots this one is composed of, in record order. Empty on a
    /// leaf slot such as RightHand.
    public let parents: [FormID]
    /// DATA — uint32 boolean. True means the item fills every parent slot at
    /// once (BothHands); false means it fills one of them (EitherHand).
    public let usesAllParents: Bool
    public let skipped: ReferenceRecordTally

    public init(record: ESMRecord) throws {
        guard record.type == "EQUP" else {
            throw ESMError.malformed("expected EQUP record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var editorID: String?
        var parents: [FormID] = []
        var usesAllParents = false
        var tally = ReferenceRecordTally()
        for field in try record.fields() {
            do {
                var reader = BinaryReader(field.data)
                switch field.type {
                case "EDID": editorID = try reader.readZString()
                case "PNAM": try parents.append(contentsOf: Self.parents(field))
                case "DATA": usesAllParents = try reader.readUInt32() != 0
                default: tally.note(.unknownField(field.type))
                }
            } catch {
                tally.note(.malformedField(field.type))
            }
        }
        self.editorID = editorID
        self.parents = parents
        self.usesAllParents = usesAllParents
        skipped = tally
    }

    /// The packed FormID array in one PNAM. A trailing partial FormID is a mod
    /// quirk: the whole-entry prefix still decodes and the remainder is
    /// dropped rather than throwing away the parents that did parse.
    private static func parents(_ field: ESMField) throws -> [FormID] {
        var reader = BinaryReader(field.data)
        var parents: [FormID] = []
        for _ in 0 ..< (field.data.count / 4) {
            let parent = try FormID(reader.readUInt32())
            guard !parent.isNull else { continue }
            parents.append(parent)
        }
        return parents
    }
}
