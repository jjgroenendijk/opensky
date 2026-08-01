// Satellite of RecordTextDump: the decoded-summary lines for the M12.1.1
// inventory record families. Split out so `RecordTextDump.decodedSummary`
// stays inside the strict-lint cyclomatic-complexity cap — its switch would
// otherwise carry fifteen cases.
//
// Feeds both `openskycli record --type WEAP` and the Asset Browser detail
// pane (docs/tools/preview-gui.md); one implementation, two surfaces.

import Foundation

nonisolated extension RecordTextDump {
    /// Decoded view for CONT, MISC, BOOK, ALCH, INGR, WEAP and AMMO. Nil for
    /// anything else, so the caller falls through to the raw field list.
    static func itemSummary(record: ESMRecord, localized: Bool) -> String? {
        switch record.type {
        case "CONT": containerSummary(record: record, localized: localized)
        case "MISC": miscSummary(record: record, localized: localized)
        case "BOOK": bookSummary(record: record, localized: localized)
        case "ALCH": ingestibleSummary(record: record, localized: localized)
        case "INGR": ingredientSummary(record: record, localized: localized)
        case "WEAP": weaponSummary(record: record, localized: localized)
        case "AMMO": ammunitionSummary(record: record, localized: localized)
        default: nil
        }
    }

    private static func containerSummary(record: ESMRecord, localized: Bool) -> String? {
        guard let container = try? Container(record: record, localized: localized) else {
            return nil
        }
        let entries = container.entries
            .prefix(8)
            .map { "\($0.item)x\($0.count)" }
            .joined(separator: ", ")
        let more = container.entries.count > 8 ? ", ..." : ""
        return "decoded CONT: editorID \(container.base.editorID ?? "-"), "
            + "\(container.entries.count) entries [\(entries)\(more)], "
            + "flags 0x\(String(container.flags.rawValue, radix: 16))"
    }

    private static func miscSummary(record: ESMRecord, localized: Bool) -> String? {
        guard let item = try? MiscItem(record: record, localized: localized) else { return nil }
        return "decoded MISC: " + shared(item.fields, item.itemValue)
    }

    private static func bookSummary(record: ESMRecord, localized: Bool) -> String? {
        guard let book = try? Book(record: record, localized: localized) else { return nil }
        let teaches = switch book.teaches {
        case .nothing: "nothing"
        case let .skill(index): "skill \(index)"
        case let .spell(spell): "spell \(spell)"
        }
        return "decoded BOOK: " + shared(book.fields, book.itemValue)
            + ", teaches \(teaches), text \(book.text == nil ? "absent" : "present")"
    }

    private static func ingestibleSummary(record: ESMRecord, localized: Bool) -> String? {
        guard let item = try? Ingestible(record: record, localized: localized) else { return nil }
        return "decoded ALCH: " + shared(item.fields, item.itemValue)
            + ", \(item.effects.count) effects, "
            + "flags 0x\(String(item.flags.rawValue, radix: 16))"
    }

    private static func ingredientSummary(record: ESMRecord, localized: Bool) -> String? {
        guard let item = try? Ingredient(record: record, localized: localized) else { return nil }
        return "decoded INGR: " + shared(item.fields, item.itemValue)
            + ", \(item.effects.count) effects, auto-calc value \(item.autoCalcValue)"
    }

    private static func weaponSummary(record: ESMRecord, localized: Bool) -> String? {
        guard let weapon = try? Weapon(record: record, localized: localized) else { return nil }
        let animation = weapon.animationType.map { "\($0)" } ?? "unknown"
        let critical = weapon.criticalData.map { "\($0.damage)" } ?? "-"
        return "decoded WEAP: " + shared(weapon.fields, weapon.itemValue)
            + String(
                format: ", damage %d, %@, speed %.2f, reach %.2f, critical %@",
                Int(weapon.damage), animation, weapon.speed, weapon.reach, critical
            )
    }

    private static func ammunitionSummary(record: ESMRecord, localized: Bool) -> String? {
        guard let ammo = try? Ammunition(record: record, localized: localized) else { return nil }
        let projectile = ammo.projectile.map(\.description) ?? "-"
        return "decoded AMMO: " + shared(ammo.fields, ammo.itemValue)
            + String(format: ", damage %.1f, projectile %@", ammo.damage, projectile)
    }

    /// The editor id / name / value / weight / keyword prefix every carryable
    /// family shares, so the seven summaries above differ only where the
    /// records do.
    private static func shared(
        _ fields: InventoryItemFields,
        _ itemValue: ItemValue
    ) -> String {
        let name = switch fields.name {
        case let .inline(text): "\"\(text)\""
        case let .tableID(id): "string #\(id)"
        case nil: "-"
        }
        return String(
            format: "editorID %@, name %@, value %d, weight %.2f, %d keywords",
            fields.editorID ?? "-",
            name,
            Int(itemValue.value),
            itemValue.weight,
            fields.keywords.keywords.count
        )
    }
}
