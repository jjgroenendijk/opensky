// M19 shout-family summaries — SHOU, WOOP, LVSP, DUAL and EQUP — kept out of
// RecordTextDumpMagic.swift so both files stay inside the strict-lint file-length
// cap. The formatter feeds both `openskycli record` and the Asset Browser.

import Foundation

nonisolated extension RecordTextDump {
    static func shoutFamilySummary(
        record: ESMRecord,
        localized: Bool,
        magicContext: MagicContext?
    ) -> String? {
        switch record.type {
        case "SHOU": shoutSummary(record, localized, magicContext)
        case "WOOP": wordOfPowerSummary(record, localized)
        case "LVSP": leveledSpellSummary(record, magicContext)
        case "DUAL": dualCastSummary(record)
        case "EQUP": equipSlotSummary(record, magicContext)
        default: nil
        }
    }

    /// SHOU: the header links plus the SNAM word run. Without a magic context
    /// the words still print, by raw FormID, because the names live in the
    /// WOOP and SPEL records the context indexes.
    private static func shoutSummary(
        _ record: ESMRecord,
        _ localized: Bool,
        _ context: MagicContext?
    ) -> String? {
        guard let shout = try? Shout(record: record, localized: localized) else { return nil }
        var line = "decoded SHOU: editorID \(shout.editorID ?? "-"), "
            + "name \(displayText(shout.name)), "
            + "description \(displayText(shout.description)), "
            + "menu display object \(shout.menuDisplayObject?.description ?? "NULL"), "
            + "\(shout.words.count) words, skipped \(shout.skipped.total)"
        let rows: [String] = if let context {
            context.shouts
                .join(shout: shout, sourcePlugin: context.sourcePlugin, spells: context.spells)
                .map { word in
                    String(
                        format: "    %@ — spell %@, recovery %.2fs",
                        word.wordName,
                        word.spellName,
                        word.entry.recoveryTime
                    )
                }
        } else {
            shout.words.map { entry in
                String(
                    format: "    %@ — spell %@, recovery %.2fs",
                    entry.word?.description ?? "NULL",
                    entry.spell?.description ?? "NULL",
                    entry.recoveryTime
                )
            }
        }
        line += "\n  words (\(rows.count)):"
        return ([line] + rows).joined(separator: "\n")
    }

    private static func wordOfPowerSummary(
        _ record: ESMRecord,
        _ localized: Bool
    ) -> String? {
        guard let word = try? WordOfPower(record: record, localized: localized) else {
            return nil
        }
        return "decoded WOOP: editorID \(word.editorID ?? "-"), "
            + "word \(displayText(word.name)), "
            + "translation \(displayText(word.translation)), "
            + "skipped \(word.skipped.total)"
    }

    /// LVSP through the same leveled-list decoder LVLN and LVLI use; the
    /// entries name a SPEL or another LVSP, so the spell store names them.
    private static func leveledSpellSummary(
        _ record: ESMRecord,
        _ context: MagicContext?
    ) -> String? {
        guard let list = try? LeveledList(record: record) else { return nil }
        let line = "decoded LVSP: editorID \(list.editorID ?? "-"), "
            + "chance none \(list.chanceNone)%, flags 0x"
            + String(format: "%02X", list.flags.rawValue)
            + ", \(list.entries.count) entries"
        let rows = list.entries.map { entry in
            let name = context.map {
                $0.spells.displayString(for: entry.reference, fromPlugin: $0.sourcePlugin)
            } ?? entry.reference.description
            return "    level \(entry.level) — \(name) × \(entry.count)"
        }
        return ([line + "\n  entries (\(rows.count)):"] + rows).joined(separator: "\n")
    }

    /// DUAL: the five art links stay raw. Nothing indexes PROJ, EXPL, EFSH,
    /// ARTO or IPDS yet, and printing a FormID honestly beats inventing a name.
    private static func dualCastSummary(_ record: ESMRecord) -> String? {
        guard let dual = try? DualCastData(record: record) else { return nil }
        var line = "decoded DUAL: editorID \(dual.editorID ?? "-")"
        guard let art = dual.art else {
            return line + ", DATA malformed, skipped \(dual.skipped.total)"
        }
        line += ", projectile \(art.projectile?.description ?? "NULL")"
        line += ", explosion \(art.explosion?.description ?? "NULL")"
        line += ", effect shader \(art.effectShader?.description ?? "NULL")"
        line += ", hit effect art \(art.hitEffectArt?.description ?? "NULL")"
        line += ", impact data set \(art.impactDataSet?.description ?? "NULL")"
        line += ", inherit scale [\(inheritScaleText(art.inheritScale))]"
        return line + ", skipped \(dual.skipped.total)"
    }

    /// EQUP: the parent slots by name and the hands the slot resolves to,
    /// which is exactly what `EquipmentCatalog` reads it for.
    private static func equipSlotSummary(
        _ record: ESMRecord,
        _ context: MagicContext?
    ) -> String? {
        guard let slot = try? EquipSlot(record: record) else { return nil }
        let parents = slot.parents.map { parent in
            context.map { $0.equipSlots.displayString(for: parent, fromPlugin: $0.sourcePlugin) }
                ?? parent.description
        }
        var line = "decoded EQUP: editorID \(slot.editorID ?? "-"), "
            + "parents [\(parents.joined(separator: ", "))], "
            + "use all parents \(slot.usesAllParents)"
        if let context {
            let hands = context.equipSlots.hands(
                of: slot.formID,
                fromPlugin: context.sourcePlugin
            ) ?? EquipSlotHands.hands(of: slot) { _ in nil }
            line += ", hands \(handSlotsText(hands))"
        }
        return line + ", skipped \(slot.skipped.total)"
    }

    private static func inheritScaleText(_ scale: DualCastData.InheritScale) -> String {
        var names: [String] = []
        if scale.contains(.hitEffectArt) {
            names.append("hit effect art")
        }
        if scale.contains(.projectile) {
            names.append("projectile")
        }
        if scale.contains(.explosion) {
            names.append("explosion")
        }
        return names.isEmpty ? "none" : names.joined(separator: ", ")
    }

    static func handSlotsText(_ hands: HandSlots) -> String {
        switch hands {
        case .bothHands: "both"
        case .rightHand: "right"
        case .leftHand: "left"
        default: "none"
        }
    }

    private static func displayText(_ value: LString?) -> String {
        switch value {
        case let .inline(text): "\"\(text)\""
        case let .tableID(id): "string #\(id)"
        case nil: "-"
        }
    }
}
