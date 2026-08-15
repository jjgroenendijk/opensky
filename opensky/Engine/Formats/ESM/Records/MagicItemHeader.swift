// The identity run SPEL and SCRL open with, decoded once.
//
// Both records start with the same subrecords the carryable families use —
// EDID, OBND, FULL, KSIZ/KWDA, and on SCRL also MODL, YNAM and ZNAM — followed
// by three links and texts that only the magic-item family carries: MDOB, ETYP
// and DESC. `InventoryItemFields` already owns the first group, so this
// accumulator composes it and adds the second.
//
// References:
//   UESP "Skyrim Mod:Mod File Format/SPEL" and ".../SCRL" field tables
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas: `wbRecord(SPEL, ...)` line
//   9980 opens `wbEDID, wbObjectBounds, wbFULL, wbKeywords, wbMDOB, wbETYP,
//   wbDESCReq`; `wbRecord(SCRL, ...)` line 10025 adds `wbGenericModel`,
//   `wbYNAM` and `wbZNAM`.
// Layout documented in docs/formats/magic-records.md.

import Foundation

nonisolated struct MagicItemHeader {
    /// EDID, FULL, OBND, KSIZ/KWDA and, on SCRL, MODL/ICON/YNAM/ZNAM.
    var fields = InventoryItemFields()
    /// DESC — the spell or scroll description shown in the magic menu. Empty
    /// on a scroll means the game concatenates the effect descriptions.
    var description: LString?
    /// MDOB — STAT shown in the menu preview.
    var menuDisplayObject: FormID?
    /// ETYP — EQUP equip slot. Resolved by 19.4; decoded and left raw here.
    var equipType: FormID?

    init() {}

    /// Decodes `field` when it belongs to the shared header and reports
    /// whether it was consumed.
    mutating func decode(field: ESMField, localized: Bool) throws -> Bool {
        if try fields.decode(field: field, localized: localized) {
            return true
        }
        switch field.type {
        case "DESC":
            description = try LString(field: field, localized: localized)
        case "MDOB":
            menuDisplayObject = try InventoryItemFields.optionalFormID(field)
        case "ETYP":
            equipType = try InventoryItemFields.optionalFormID(field)
        default:
            return false
        }
        return true
    }
}
