// EQUP record: one equip slot, the record every ETYP link on a weapon, spell,
// scroll, potion or piece of armour points at. Skyrim.esm authors seven —
// RightHand, LeftHand, EitherHand, BothHands, Shield, Voice and Potion — and
// the whole vocabulary is expressed by two things: which other slots a slot
// names as parents, and whether it takes all of them or one of them.
//
// Observed in the vanilla master (probe against the read-only install):
//
//   RightHand   parents []                        use all parents 0
//   LeftHand    parents []                        use all parents 0
//   EitherHand  parents [LeftHand, RightHand]     use all parents 0
//   BothHands   parents [LeftHand, RightHand]     use all parents 1
//   Shield      parents [LeftHand]                use all parents 1
//   Voice       parents []                        use all parents 0
//   Potion      parents []                        use all parents 0
//
// So "use all parents" is what separates a two-handed weapon from a
// hand-of-your-choice weapon, and a parentless slot is a leaf the engine
// itself names. `EquipSlotHands` turns that graph into `HandSlots`.
//
// PNAM is a single subrecord holding a packed FormID array (xEdit
// `wbArray(PNAM, 'Slot Parents', wbFormID(...))`). A record that spreads its
// parents over several PNAM fields still decodes, because every PNAM appends.
//
// References:
//   UESP "Skyrim Mod:Mod File Format/EQUP"
//     https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/EQUP
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas
//     `wbRecord(EQUP, 'Equip Type', ...)` line 7192.
// Layout documented in docs/formats/magic-records.md.

import Foundation

nonisolated struct EquipSlot: Equatable {
    let formID: FormID
    let editorID: String?
    /// PNAM — the slots this one is composed of, in record order. Empty on a
    /// leaf slot such as RightHand.
    let parents: [FormID]
    /// DATA — uint32 boolean. True means the item fills every parent slot at
    /// once (BothHands); false means it fills one of them (EitherHand).
    let usesAllParents: Bool
    let skipped: ReferenceRecordTally

    init(record: ESMRecord) throws {
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
