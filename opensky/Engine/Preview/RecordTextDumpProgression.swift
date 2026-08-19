// M20 progression summaries — AVIF and PERK — kept out of RecordTextDump's
// capped dispatch switch. The formatter feeds both `openskycli record` and the
// Asset Browser.

import Foundation

nonisolated extension RecordTextDump {
    static func progressionSummary(
        _ record: ESMRecord,
        _ localized: Bool,
        _ context: MagicContext?
    ) -> String? {
        switch record.type {
        case "AVIF": actorValueInformationSummary(record, localized, context)
        case "PERK": perkSummary(record, localized, context)
        default: nil
        }
    }

    /// AVIF: the identity line, then the advancement parameters and the perk
    /// grid when the record carries them. A perk-tree box prints the name of
    /// the PERK it grants when the dump was given a perk store, and the raw
    /// link when it was not.
    private static func actorValueInformationSummary(
        _ record: ESMRecord,
        _ localized: Bool,
        _ context: MagicContext?
    ) -> String? {
        guard let value = try? ActorValueInformation(record: record, localized: localized) else {
            return nil
        }
        let actorValue = value.vanillaActorValueIndex.map {
            "\(ActorValueIdentity.description(of: $0)) (index \($0))"
        } ?? "not a vanilla actor value"
        var lines = [
            "decoded AVIF: editorID \(value.editorID ?? "-"), "
                + "name \(nameText(value.name)), "
                + "abbreviation \(value.abbreviation ?? "-"), "
                + "actor value \(actorValue), "
                + "category \(value.skillCategory?.description ?? "-"), "
                + "skipped \(value.skipped.total)"
        ]
        if let use = value.skillUse {
            lines.append(String(
                format: "  skill use: use mult %.4f, use offset %.4f, "
                    + "improve mult %.4f, improve offset %.4f",
                use.useMultiplier,
                use.useOffset,
                use.improveMultiplier,
                use.improveOffset
            ))
        }
        lines.append(contentsOf: perkTreeLines(value.perkTree, context))
        return lines.joined(separator: "\n")
    }

    private static func nameText(_ value: LString?) -> String {
        switch value {
        case let .inline(text): "\"\(text)\""
        case let .tableID(id): "string #\(id)"
        case nil: "-"
        }
    }

    private static func perkTreeLines(
        _ nodes: [PerkTreeNode],
        _ context: MagicContext?
    ) -> [String] {
        guard !nodes.isEmpty else { return [] }
        let rows = nodes.map { node in
            String(
                format: "    #%d perk %@, grid (%d,%d) offset (%.3f,%.3f), "
                    + "parent required %@, lines to [%@]",
                Int(node.index),
                node.perk.map { perkText($0, context) } ?? "NULL",
                Int(node.position.column),
                Int(node.position.row),
                node.position.horizontal,
                node.position.vertical,
                node.parentRequired ? "yes" : "no",
                node.connections.map(String.init).joined(separator: ", ")
            )
        }
        return ["  perk tree (\(nodes.count) nodes):"] + rows
    }

    /// PERK: the header line, the availability conditions, then one block per
    /// effect with its typed payload, its condition tabs and its decoded
    /// function data.
    private static func perkSummary(
        _ record: ESMRecord,
        _ localized: Bool,
        _ context: MagicContext?
    ) -> String? {
        guard let perk = try? Perk(record: record, localized: localized) else { return nil }
        let header = perk.data.map {
            String(
                format: "level %d, declared ranks %d, %@%@%@",
                Int($0.level),
                Int($0.rankCount),
                $0.isPlayable ? "playable" : "not playable",
                $0.isTrait ? ", trait" : "",
                $0.isHidden ? ", hidden" : ""
            )
        } ?? "DATA malformed"
        let skips = perk.skipped.isEmpty
            ? ""
            : ", skipped " + perk.skipped.ranked.map { "\($0.name):\($0.count)" }
            .joined(separator: " ")
        var lines = [
            "decoded PERK: editorID \(perk.editorID ?? "-"), "
                + "name \(nameText(perk.name)), \(header), "
                + "next perk \(perk.nextPerk.map { perkText($0, context) } ?? "-"), "
                + "\(perk.effects.count) effects, "
                + "\(perk.script.scripts.count) scripts"
                + skips
        ]
        lines.append(contentsOf: conditionLines(
            perk.conditions,
            title: "  conditions",
            indent: "    "
        ))
        for (offset, effect) in perk.effects.enumerated() {
            lines.append(contentsOf: perkEffectLines(effect, index: offset, context: context))
        }
        return lines.joined(separator: "\n")
    }

    private static func perkEffectLines(
        _ effect: PerkEffect,
        index: Int,
        context: MagicContext?
    ) -> [String] {
        var lines = [
            "  effect \(index): \(effect.type) rank \(effect.displayRank), "
                + "priority \(effect.priority)"
                + (effect.isTerminated ? "" : " [NO PRKF]")
        ]
        lines.append(contentsOf: perkEffectDataLines(effect, context))
        if let type = effect.functionType {
            var line = "    function data: type \(type)"
            if let data = effect.functionData {
                line += ", \(data)"
            }
            if let label = effect.buttonLabel {
                line += ", label \(nameText(label))"
            }
            if let flags = effect.scriptFlags {
                line += String(
                    format: ", flags 0x%04X, fragment %d",
                    Int(flags.options.rawValue),
                    Int(flags.fragmentIndex)
                )
            }
            lines.append(line)
        }
        for (offset, tab) in effect.conditionTabs.enumerated() {
            lines.append(contentsOf: conditionLines(
                tab.conditions,
                title: "    tab \(offset) (run on \(tab.runOn))",
                indent: "      "
            ))
        }
        return lines
    }

    private static func perkEffectDataLines(
        _ effect: PerkEffect,
        _ context: MagicContext?
    ) -> [String] {
        switch effect.data {
        case let .quest(quest, stage):
            ["    quest \(quest?.description ?? "NULL") stage \(stage)"]
        case let .ability(spell):
            ["    ability \(spellText(spell, context))"]
        case let .entryPoint(payload):
            [
                "    entry point \(payload.entryPoint), "
                    + "function \(payload.function), "
                    + "\(payload.conditionTabCount) condition tab(s) declared"
                    + (effect.spell.map { ", spell \(spellText($0, context))" } ?? "")
            ]
        case let .raw(data):
            ["    DATA \(data.count) raw bytes"]
        case nil:
            ["    no DATA"]
        }
    }

    /// One line per CTDA, in the same `<function> <operator> <value>` shape the
    /// runtime-state condition readout prints.
    private static func conditionLines(
        _ list: ConditionList,
        title: String,
        indent: String
    ) -> [String] {
        guard !list.isEmpty else { return [] }
        let rows = list.conditions.map { condition in
            indent + RuntimeStateConditionRunner.describe(
                condition,
                registry: ConditionFunctionRegistry.standard
            )
        }
        return ["\(title) (\(list.conditions.count)):"] + rows
    }

    private static func perkText(_ id: FormID, _ context: MagicContext?) -> String {
        guard let perks = context?.perks else { return id.description }
        return perks.displayString(for: id, fromPlugin: context?.sourcePlugin ?? "")
    }

    private static func spellText(_ id: FormID?, _ context: MagicContext?) -> String {
        guard let id else { return "NULL" }
        guard let context else { return id.description }
        return context.spells.displayString(for: id, fromPlugin: context.sourcePlugin)
    }
}
