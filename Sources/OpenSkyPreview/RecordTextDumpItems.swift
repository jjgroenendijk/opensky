// Satellite of RecordTextDump: decoded-summary lines for the inventory record
// types. A separate file keeps `decodedSummary` under the complexity cap.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated extension RecordTextDump {
    /// Decoded view for CONT, the carryable item records, ARMA, and PROJ. Nil for anything else, so
    /// the caller falls through to the raw
    /// field list.
    public static func itemSummary(
        record: ESMRecord,
        localized: Bool,
        keywordContext: KeywordContext?,
        magicContext: MagicContext?
    ) throws -> String? {
        switch record.type {
        case "CONT": try containerSummary(record: record, localized: localized)
        case "MISC": try miscSummary(record, localized, keywordContext)
        case "KEYM", "SLGM", "APPA": try minorItemSummary(record, localized, keywordContext)
        case "BOOK": try bookSummary(record, localized, keywordContext, magicContext)
        case "ALCH": try ingestibleSummary(record, localized, keywordContext, magicContext)
        case "INGR": try ingredientSummary(record, localized, keywordContext, magicContext)
        case "WEAP": try weaponSummary(record, localized, keywordContext, magicContext)
        case "AMMO": try ammunitionSummary(record, localized, keywordContext)
        case "ARMO": try armorSummary(record, localized, keywordContext, magicContext)
        case "ARMA": try armorAddonSummary(record: record)
        case "PROJ": try projectileSummary(record: record)
        default: nil
        }
    }

    /// PROJ is not an item, but it is what an AMMO `projectile` link points at.
    private static func projectileSummary(record: ESMRecord) throws -> String? {
        let projectile = try Projectile(record: record)
        let kind = projectile.kind.map { "\($0)" } ?? "unknown"
        return String(
            format: """
            decoded PROJ: editorID %@, %@, speed %.1f, gravity %.3f, range %.1f, \
            lifetime %.2f, radius %.1f, flags 0x%04X
            """,
            projectile.editorID ?? "-",
            kind,
            projectile.speed,
            projectile.gravityFactor,
            projectile.range,
            projectile.lifetime,
            projectile.collisionRadius,
            projectile.flags.rawValue
        )
    }

    private static func armorSummary(
        _ record: ESMRecord,
        _ localized: Bool,
        _ context: KeywordContext?,
        _ magicContext: MagicContext?
    ) throws -> String? {
        let armor = try Armor(record: record, localized: localized)
        let slots = armor.bodyTemplate.map { "0x\(String($0.slots.rawValue, radix: 16))" } ?? "-"
        return "decoded ARMO: editorID \(armor.editorID ?? "-"), "
            + "value \(armor.itemValue.value), "
            + "weight \(String(format: "%.2f", armor.itemValue.weight)), "
            + keywordText(armor.keywords, context: context) + ", "
            + "slots \(slots), rating \(armor.armorRating), "
            + "\(armor.armatures.count) armatures"
            + enchantmentText(armor.enchantment, charge: nil, context: magicContext)
    }

    /// The ENCH an item names, resolved to a name once a magic context is
    /// present. Empty for an unenchanted record, so only enchanted items grow
    /// the line. A charge is only ever present on a weapon: ARMO has no EAMT.
    private static func enchantmentText(
        _ id: FormID?,
        charge: UInt16?,
        context: MagicContext?
    ) -> String {
        guard let id else { return "" }
        let name = if let context {
            context.enchantments.displayString(for: id, fromPlugin: context.sourcePlugin)
        } else {
            id.description
        }
        return ", enchantment \(name)" + (charge.map { ", charge \($0)" } ?? "")
    }

    /// ARMA draw priorities are what equip-slot arbitration compares.
    private static func armorAddonSummary(record: ESMRecord) throws -> String? {
        let addon = try ArmorAddon(record: record)
        let slots = addon.bodyTemplate.map { "0x\(String($0.slots.rawValue, radix: 16))" } ?? "-"
        return "decoded ARMA: editorID \(addon.editorID ?? "-"), "
            + "slots \(slots), race \(addon.primaryRace?.description ?? "-"), "
            + "+\(addon.additionalRaces.count) races, "
            + "priority male \(addon.malePriority) female \(addon.femalePriority), "
            + "weapon adjust \(String(format: "%.2f", addon.weaponAdjust)), "
            + "male model \(addon.maleModelPath ?? "-")"
    }

    private static func containerSummary(record: ESMRecord, localized: Bool) throws -> String? {
        let container = try Container(record: record, localized: localized)
        let entries = container.entries
            .prefix(8)
            .map { "\($0.item)x\($0.count)" }
            .joined(separator: ", ")
        let more = container.entries.count > 8 ? ", ..." : ""
        return "decoded CONT: editorID \(container.base.editorID ?? "-"), "
            + "\(container.entries.count) entries [\(entries)\(more)], "
            + "flags 0x\(String(container.flags.rawValue, radix: 16))"
    }

    private static func miscSummary(
        _ record: ESMRecord,
        _ localized: Bool,
        _ context: KeywordContext?
    ) throws -> String? {
        let item = try MiscItem(record: record, localized: localized)
        return "decoded MISC: " + sharedItemText(item.fields, item.itemValue, context)
    }

    private static func bookSummary(
        _ record: ESMRecord,
        _ localized: Bool,
        _ context: KeywordContext?,
        _ magicContext: MagicContext?
    ) throws -> String? {
        let book = try Book(record: record, localized: localized)
        let teaches = switch book.teaches {
        case .nothing: "nothing"
        case let .skill(index): "skill \(ActorValueIdentity.description(of: index))"
        case let .spell(spell): "spell \(spellText(spell, context: magicContext))"
        }
        return "decoded BOOK: " + sharedItemText(book.fields, book.itemValue, context)
            + ", teaches \(teaches), text \(book.text == nil ? "absent" : "present")"
    }

    private static func ingestibleSummary(
        _ record: ESMRecord,
        _ localized: Bool,
        _ context: KeywordContext?,
        _ magicContext: MagicContext?
    ) throws -> String? {
        let item = try Ingestible(record: record, localized: localized)
        return "decoded ALCH: " + sharedItemText(item.fields, item.itemValue, context)
            + ", " + effectText(item.effects, context: magicContext) + ", "
            + "flags 0x\(String(item.flags.rawValue, radix: 16))"
    }

    private static func ingredientSummary(
        _ record: ESMRecord,
        _ localized: Bool,
        _ context: KeywordContext?,
        _ magicContext: MagicContext?
    ) throws -> String? {
        let item = try Ingredient(record: record, localized: localized)
        return "decoded INGR: " + sharedItemText(item.fields, item.itemValue, context)
            + ", " + effectText(item.effects, context: magicContext)
            + ", auto-calc value \(item.autoCalcValue)"
    }

    private static func weaponSummary(
        _ record: ESMRecord,
        _ localized: Bool,
        _ context: KeywordContext?,
        _ magicContext: MagicContext?
    ) throws -> String? {
        let weapon = try Weapon(record: record, localized: localized)
        let animation = weapon.animationType.map { "\($0)" } ?? "unknown"
        let critical = weapon.criticalData.map { "\($0.damage)" } ?? "-"
        let criticalEffect = weapon.criticalData?.effect.map {
            ", critical effect " + spellText($0, context: magicContext)
        } ?? ""
        return "decoded WEAP: " + sharedItemText(weapon.fields, weapon.itemValue, context)
            + String(
                format: ", damage %d, %@, speed %.2f, reach %.2f, critical %@",
                Int(weapon.damage), animation, weapon.speed, weapon.reach, critical
            )
            + criticalEffect
            + enchantmentText(
                weapon.enchantment,
                charge: weapon.enchantmentCharge,
                context: magicContext
            )
    }

    /// Names the SPEL a book teaches or a weapon's critical applies, once a
    /// magic context is present; a bare FormID otherwise.
    private static func spellText(_ id: FormID, context: MagicContext?) -> String {
        guard let context else { return id.description }
        return context.spells.displayString(for: id, fromPlugin: context.sourcePlugin)
    }

    private static func ammunitionSummary(
        _ record: ESMRecord,
        _ localized: Bool,
        _ context: KeywordContext?
    ) throws -> String? {
        let ammo = try Ammunition(record: record, localized: localized)
        let projectile = ammo.projectile.map(\.description) ?? "-"
        return "decoded AMMO: " + sharedItemText(ammo.fields, ammo.itemValue, context)
            + String(format: ", damage %.1f, projectile %@", ammo.damage, projectile)
    }

    /// The editor id / name / value / weight / keyword prefix every carryable
    /// family shares, so the summaries differ only where the records do.
    static func sharedItemText(
        _ fields: InventoryItemFields,
        _ itemValue: ItemValue,
        _ context: KeywordContext?
    ) -> String {
        let name = switch fields.name {
        case let .inline(text): "\"\(text)\""
        case let .tableID(id): "string #\(id)"
        case nil: "-"
        }
        return String(
            format: "editorID %@, name %@, value %d, weight %.2f, %@",
            fields.editorID ?? "-",
            name,
            Int(itemValue.value),
            itemValue.weight,
            keywordText(fields.keywords, context: context)
        )
    }

    static func keywordText(
        _ keywords: KeywordList,
        context: KeywordContext?
    ) -> String {
        let names = if let context {
            keywords.displayStrings(fromPlugin: context.sourcePlugin, using: context.store)
        } else {
            keywords.keywords.map(\.description)
        }
        return "keywords [\(names.joined(separator: ", "))]"
    }

    private static func effectText(
        _ effects: [MagicItemEffect],
        context: MagicContext?
    ) -> String {
        let names = effects.map { effect in
            if let context {
                return context.effects.displayString(
                    for: effect.effect,
                    fromPlugin: context.sourcePlugin
                )
            }
            return effect.effect.description
        }
        return "\(effects.count) effects [\(names.joined(separator: ", "))]"
    }
}
