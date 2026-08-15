// SPEL record: the container the caster runtime consumes. A spell is the
// shared magic-item header, the 36-byte SPIT casting struct, and the same
// EFID/EFIT/CTDA effect run ALCH and INGR already decode.
//
// Decode policy follows MGEF: a wrong record type throws, an individual
// malformed field is tallied and the rest of the record still decodes, and a
// truncated SPIT leaves `data == nil` rather than losing the effect list — the
// effects are what a caster needs even when the header is unreadable.
//
// Skipped for now: VMAD script attachments, which no spell consumer reads yet.
//
// References:
//   UESP "Skyrim Mod:Mod File Format/SPEL"
//     https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/SPEL
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas `wbRecord(SPEL, 'Spell', ...)`
//     line 9980.
// Layout documented in docs/formats/magic-records.md.

import Foundation

nonisolated struct Spell {
    let formID: FormID
    let header: MagicItemHeader
    /// SPIT. Nil when the field is absent or too short to decode.
    let data: SpellItemData?
    let effects: [MagicItemEffect]
    let skipped: MagicEffectTally

    var editorID: String? {
        header.fields.editorID
    }

    var name: LString? {
        header.fields.name
    }

    init(record: ESMRecord, localized: Bool) throws {
        guard record.type == "SPEL" else {
            throw ESMError.malformed("expected SPEL record, got \(record.type)")
        }
        var decoder = MagicItemFields(localized: localized)
        for field in try record.fields() {
            decoder.decode(field)
        }
        formID = FormID(record.formID)
        header = decoder.header
        data = decoder.data
        effects = decoder.finishEffects()
        skipped = decoder.skipped
    }
}

/// Field accumulator shared by the SPEL and SCRL decoders: the header, the
/// SPIT struct, the effect run, and the unread-field tally. SCRL adds DATA on
/// top through `decodeItemValue`.
nonisolated struct MagicItemFields {
    let localized: Bool
    private(set) var header = MagicItemHeader()
    private(set) var data: SpellItemData?
    private(set) var skipped = MagicEffectTally()
    private var effects = MagicItemEffectList()

    init(localized: Bool) {
        self.localized = localized
    }

    /// Decodes one field, tallying anything unread or malformed. Returns
    /// whether the field was consumed so SCRL can add its own cases.
    @discardableResult
    mutating func decode(_ field: ESMField) -> Bool {
        do {
            if try header.decode(field: field, localized: localized) {
                return true
            }
            if field.type == "SPIT" {
                data = try SpellItemData(field: field)
                return true
            }
            if try effects.decode(field: field) {
                return true
            }
            skipped.note(.unknownField(field.type))
            return false
        } catch {
            skipped.note(.malformedField(field.type))
            return true
        }
    }

    mutating func finishEffects() -> [MagicItemEffect] {
        effects.finish()
    }
}

/// A decoded SPEL or SCRL, so one store and one inspector path can carry both.
nonisolated enum MagicCastingRecord {
    case spell(Spell)
    case scroll(Scroll)

    var recordType: FourCC {
        switch self {
        case .spell: "SPEL"
        case .scroll: "SCRL"
        }
    }

    var editorID: String? {
        switch self {
        case let .spell(spell): spell.editorID
        case let .scroll(scroll): scroll.editorID
        }
    }

    var name: LString? {
        switch self {
        case let .spell(spell): spell.name
        case let .scroll(scroll): scroll.name
        }
    }

    var data: SpellItemData? {
        switch self {
        case let .spell(spell): spell.data
        case let .scroll(scroll): scroll.data
        }
    }

    var effects: [MagicItemEffect] {
        switch self {
        case let .spell(spell): spell.effects
        case let .scroll(scroll): scroll.effects
        }
    }

    var skipped: MagicEffectTally {
        switch self {
        case let .spell(spell): spell.skipped
        case let .scroll(scroll): scroll.skipped
        }
    }
}
