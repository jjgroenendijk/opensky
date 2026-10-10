// The identity fields SPEL and SCRL start with, decoded once. Composes
// `InventoryItemFields` and adds MDOB, ETYP, and DESC.
// Layout and sources: docs/formats/magic-records.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct MagicItemHeader: Sendable {
    /// EDID, FULL, OBND, KSIZ/KWDA and, on SCRL, MODL/ICON/YNAM/ZNAM.
    public var fields = InventoryItemFields()
    /// DESC — the spell or scroll description shown in the magic menu. Empty
    /// on a scroll means the game concatenates the effect descriptions.
    public var description: LString?
    /// MDOB — STAT shown in the menu preview.
    public var menuDisplayObject: FormID?
    /// ETYP — EQUP equip slot, left raw here and resolved through
    /// `EquipSlotStore` by whichever consumer needs the slot.
    public var equipType: FormID?

    public init() {}

    /// Decodes `field` when it belongs to the shared header and reports
    /// whether it was consumed.
    public mutating func decode(field: ESMField, localized: Bool) throws -> Bool {
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
