// SPEL spell: the magic-item header, the 36-byte SPIT, and the effect run.
// A truncated SPIT leaves `data == nil` but keeps the effects, which are what
// a caster needs. Layout and sources: docs/formats/magic-records.md.

import Foundation
public import OpenSkyFormatsCore

nonisolated public struct Spell: Sendable {
    public let formID: FormID
    public let header: MagicItemHeader
    /// SPIT. Nil when the field is absent or too short to decode.
    public let data: SpellItemData?
    public let effects: [MagicItemEffect]
    public let skipped: MagicEffectTally

    public var editorID: String? {
        header.fields.editorID
    }

    public var name: LString? {
        header.fields.name
    }

    public init(record: ESMRecord, localized: Bool) throws {
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
nonisolated public struct MagicItemFields: Sendable {
    public let localized: Bool
    public private(set) var header = MagicItemHeader()
    public private(set) var data: SpellItemData?
    public private(set) var skipped = MagicEffectTally()
    private var effects = MagicItemEffectList()

    public init(localized: Bool) {
        self.localized = localized
    }

    /// Decodes one field, tallying anything unread or malformed. Returns
    /// whether the field was consumed so SCRL can add its own cases.
    @discardableResult
    public mutating func decode(_ field: ESMField) -> Bool {
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

    public mutating func finishEffects() -> [MagicItemEffect] {
        effects.finish()
    }
}

/// A decoded SPEL or SCRL, so one store and one inspector path can carry both.
nonisolated public enum MagicCastingRecord: Sendable {
    case spell(Spell)
    case scroll(Scroll)
    /// A staff enchantment, which a staff casts like a spell.
    case staff(Enchantment)

    public var recordType: FourCC {
        switch self {
        case .spell: "SPEL"
        case .scroll: "SCRL"
        case .staff: "ENCH"
        }
    }

    public var editorID: String? {
        switch self {
        case let .spell(spell): spell.editorID
        case let .scroll(scroll): scroll.editorID
        case let .staff(enchantment): enchantment.editorID
        }
    }

    public var name: LString? {
        switch self {
        case let .spell(spell): spell.name
        case let .scroll(scroll): scroll.name
        case let .staff(enchantment): enchantment.name
        }
    }

    public var data: SpellItemData? {
        switch self {
        case let .spell(spell): spell.data
        case let .scroll(scroll): scroll.data
        case let .staff(enchantment): enchantment.data.map(SpellItemData.init(staff:))
        }
    }

    /// ETYP: the EQUP slot the record links to, raw and relative to the
    /// authoring plugin. It says which hands a readied spell takes.
    public var equipType: FormID? {
        switch self {
        case let .spell(spell): spell.header.equipType
        case let .scroll(scroll): scroll.header.equipType
        case .staff: nil
        }
    }

    public var effects: [MagicItemEffect] {
        switch self {
        case let .spell(spell): spell.effects
        case let .scroll(scroll): scroll.effects
        case let .staff(enchantment): enchantment.effects
        }
    }

    public var skipped: MagicEffectTally {
        switch self {
        case let .spell(spell): spell.skipped
        case let .scroll(scroll): scroll.skipped
        case let .staff(enchantment): enchantment.skipped
        }
    }
}
