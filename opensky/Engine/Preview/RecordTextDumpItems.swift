// Satellite of RecordTextDump: the decoded-summary lines for the M12.1.1
// inventory record families. Split out so `RecordTextDump.decodedSummary`
// stays inside the strict-lint cyclomatic-complexity cap — its switch would
// otherwise carry fifteen cases.
//
// Feeds both `openskycli record --type WEAP` and the Asset Browser detail
// pane (docs/tools/preview-gui.md); one implementation, two surfaces.

import Foundation

nonisolated extension RecordTextDump {
    /// Decoded view for CONT, MISC, BOOK, ALCH, INGR, WEAP, AMMO, ARMO and
    /// ARMA. Nil for anything else, so the caller falls through to the raw
    /// field list.
    static func itemSummary(
        record: ESMRecord,
        localized: Bool,
        keywordContext: KeywordContext?,
        magicContext: MagicContext?
    ) -> String? {
        switch record.type {
        case "CONT": containerSummary(record: record, localized: localized)
        case "MISC": miscSummary(record, localized, keywordContext)
        case "BOOK": bookSummary(record, localized, keywordContext, magicContext)
        case "ALCH": ingestibleSummary(record, localized, keywordContext, magicContext)
        case "INGR": ingredientSummary(record, localized, keywordContext, magicContext)
        case "WEAP": weaponSummary(record, localized, keywordContext, magicContext)
        case "AMMO": ammunitionSummary(record, localized, keywordContext)
        case "ARMO": armorSummary(record, localized, keywordContext)
        case "ARMA": armorAddonSummary(record: record)
        case "PROJ": projectileSummary(record: record)
        default: nil
        }
    }

    /// PROJ is not carryable and so does not share the inventory prefix; it is
    /// summarized here anyway because the record an arrow points at is the one
    /// a reader chasing an AMMO's `projectile` link wants next (issue #196).
    private static func projectileSummary(record: ESMRecord) -> String? {
        guard let projectile = try? Projectile(record: record) else { return nil }
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
        _ context: KeywordContext?
    ) -> String? {
        guard let armor = try? Armor(record: record, localized: localized) else { return nil }
        let slots = armor.bodyTemplate.map { "0x\(String($0.slots.rawValue, radix: 16))" } ?? "-"
        return "decoded ARMO: editorID \(armor.editorID ?? "-"), "
            + "value \(armor.itemValue.value), "
            + "weight \(String(format: "%.2f", armor.itemValue.weight)), "
            + keywordText(armor.keywords, context: context) + ", "
            + "slots \(slots), rating \(armor.armorRating), "
            + "\(armor.armatures.count) armatures"
    }

    /// ARMA's draw priorities are what equip-slot arbitration compares
    /// (issue #178), so they are the point of this line — inspecting them on a
    /// real record is how the DNAM layout was confirmed.
    private static func armorAddonSummary(record: ESMRecord) -> String? {
        guard let addon = try? ArmorAddon(record: record) else { return nil }
        let slots = addon.bodyTemplate.map { "0x\(String($0.slots.rawValue, radix: 16))" } ?? "-"
        return "decoded ARMA: editorID \(addon.editorID ?? "-"), "
            + "slots \(slots), race \(addon.primaryRace?.description ?? "-"), "
            + "+\(addon.additionalRaces.count) races, "
            + "priority male \(addon.malePriority) female \(addon.femalePriority), "
            + "weapon adjust \(String(format: "%.2f", addon.weaponAdjust)), "
            + "male model \(addon.maleModelPath ?? "-")"
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

    private static func miscSummary(
        _ record: ESMRecord,
        _ localized: Bool,
        _ context: KeywordContext?
    ) -> String? {
        guard let item = try? MiscItem(record: record, localized: localized) else { return nil }
        return "decoded MISC: " + shared(item.fields, item.itemValue, context)
    }

    private static func bookSummary(
        _ record: ESMRecord,
        _ localized: Bool,
        _ context: KeywordContext?,
        _ magicContext: MagicContext?
    ) -> String? {
        guard let book = try? Book(record: record, localized: localized) else { return nil }
        let teaches = switch book.teaches {
        case .nothing: "nothing"
        case let .skill(index): "skill \(ActorValueIdentity.description(of: index))"
        case let .spell(spell): "spell \(spellText(spell, context: magicContext))"
        }
        return "decoded BOOK: " + shared(book.fields, book.itemValue, context)
            + ", teaches \(teaches), text \(book.text == nil ? "absent" : "present")"
    }

    private static func ingestibleSummary(
        _ record: ESMRecord,
        _ localized: Bool,
        _ context: KeywordContext?,
        _ magicContext: MagicContext?
    ) -> String? {
        guard let item = try? Ingestible(record: record, localized: localized) else { return nil }
        return "decoded ALCH: " + shared(item.fields, item.itemValue, context)
            + ", " + effectText(item.effects, context: magicContext) + ", "
            + "flags 0x\(String(item.flags.rawValue, radix: 16))"
    }

    private static func ingredientSummary(
        _ record: ESMRecord,
        _ localized: Bool,
        _ context: KeywordContext?,
        _ magicContext: MagicContext?
    ) -> String? {
        guard let item = try? Ingredient(record: record, localized: localized) else { return nil }
        return "decoded INGR: " + shared(item.fields, item.itemValue, context)
            + ", " + effectText(item.effects, context: magicContext)
            + ", auto-calc value \(item.autoCalcValue)"
    }

    private static func weaponSummary(
        _ record: ESMRecord,
        _ localized: Bool,
        _ context: KeywordContext?,
        _ magicContext: MagicContext?
    ) -> String? {
        guard let weapon = try? Weapon(record: record, localized: localized) else { return nil }
        let animation = weapon.animationType.map { "\($0)" } ?? "unknown"
        let critical = weapon.criticalData.map { "\($0.damage)" } ?? "-"
        let criticalEffect = weapon.criticalData?.effect.map {
            ", critical effect " + spellText($0, context: magicContext)
        } ?? ""
        return "decoded WEAP: " + shared(weapon.fields, weapon.itemValue, context)
            + String(
                format: ", damage %d, %@, speed %.2f, reach %.2f, critical %@",
                Int(weapon.damage), animation, weapon.speed, weapon.reach, critical
            )
            + criticalEffect
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
    ) -> String? {
        guard let ammo = try? Ammunition(record: record, localized: localized) else { return nil }
        let projectile = ammo.projectile.map(\.description) ?? "-"
        return "decoded AMMO: " + shared(ammo.fields, ammo.itemValue, context)
            + String(format: ", damage %.1f, projectile %@", ammo.damage, projectile)
    }

    /// The editor id / name / value / weight / keyword prefix every carryable
    /// family shares, so the seven summaries above differ only where the
    /// records do.
    private static func shared(
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

    private static func keywordText(
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
