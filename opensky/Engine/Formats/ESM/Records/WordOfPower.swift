// WOOP record: one word of power. Three of them make a shout, and the SHOU
// record — not this one — owns the pairing between a word and the spell it
// casts.
//
// FULL is the word written in the dragon alphabet's transliteration ("B4" for
// Bah, numbers standing in for vowel combinations in Bethesda's dragon font),
// TNAM the same word translated into the player's language. TNAM is always
// present in the vanilla masters but is frequently an empty string, so an
// empty translation is normal data rather than a decode failure.
//
// References:
//   UESP "Skyrim Mod:Mod File Format/WOOP"
//     https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/WOOP
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas
//     `wbRecord(WOOP, 'Word of Power', ...)` line 10639.
// Layout documented in docs/formats/magic-records.md.

import Foundation

nonisolated struct WordOfPower: Equatable {
    let formID: FormID
    let editorID: String?
    /// FULL — the word in dragon-font transliteration.
    let name: LString?
    /// TNAM — the word translated into the plugin's language.
    let translation: LString?
    let skipped: ReferenceRecordTally

    init(record: ESMRecord, localized: Bool) throws {
        guard record.type == "WOOP" else {
            throw ESMError.malformed("expected WOOP record, got \(record.type)")
        }
        formID = FormID(record.formID)

        var editorID: String?
        var name: LString?
        var translation: LString?
        var tally = ReferenceRecordTally()
        for field in try record.fields() {
            do {
                var reader = BinaryReader(field.data)
                switch field.type {
                case "EDID": editorID = try reader.readZString()
                case "FULL": name = try LString(field: field, localized: localized)
                case "TNAM": translation = try LString(field: field, localized: localized)
                default: tally.note(.unknownField(field.type))
                }
            } catch {
                tally.note(.malformedField(field.type))
            }
        }
        self.editorID = editorID
        self.name = name
        self.translation = translation
        skipped = tally
    }
}
