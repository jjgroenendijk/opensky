// Satellite of RecordTextDump: decoded-summary lines for ARTO and COBJ, and for
// the world objects FLOR, TACT, FURN, TREE, and ACTI.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated extension RecordTextDump {
    static func craftingSummary(
        _ record: ESMRecord,
        _ localized: Bool,
        _ context: KeywordContext?
    ) throws -> String? {
        switch record.type {
        case "ARTO":
            let art = try ArtObject(record: record)
            return "decoded ARTO: editorID \(art.editorID ?? "-"), "
                + "art type \(art.artType.map { "\($0)" } ?? "-"), "
                + "model \(art.modelPath ?? "-")" + skippedText(art.skipped)
        case "COBJ":
            return try recipeSummary(ConstructibleObject(record: record), context)
        case "FLOR", "TACT", "FURN", "TREE", "ACTI":
            return try worldObjectSummary(
                ModelBase(record: record, localized: localized), context
            )
        default:
            return nil
        }
    }

    private static func recipeSummary(
        _ recipe: ConstructibleObject,
        _ context: KeywordContext?
    ) -> String {
        let keyword = recipe.workbenchKeyword.map { keyword in
            context.map { $0.store.displayString(for: keyword, fromPlugin: $0.sourcePlugin) }
                ?? keyword.description
        } ?? "NULL"
        let line = "decoded COBJ: editorID \(recipe.editorID ?? "-"), "
            + "creates \(recipe.createdObject?.description ?? "NULL") "
            + "x\(recipe.effectiveCreatedCount), workbench \(keyword)"
            + skippedText(recipe.skipped)
        let components = recipe.components.map { "    \($0.item) x\($0.count)" }
        return ([line, "  components (\(components.count)):"] + components
            + conditionLines(recipe.conditions, title: "  conditions", indent: "    "))
            .joined(separator: "\n")
    }

    private static func worldObjectSummary(
        _ base: ModelBase,
        _ context: KeywordContext?
    ) -> String {
        var line = "decoded \(base.recordType): editorID \(base.editorID ?? "-"), "
            + "name \(displayText(base.name)), model \(base.modelPath ?? "-"), "
            + keywordText(base.keywords, context: context)
        if let workbench = base.workbench {
            line += ", workbench \(workbench.benchType)"
                + " skill \(workbench.skillName ?? "\(workbench.skillIndex)")"
        }
        if let produce = base.produce {
            let seasons = produce.seasonalChance.map { chances in
                chances.map { "\($0)%" }.joined(separator: "/")
            } ?? "-"
            line += ", produce \(produce.ingredient?.description ?? "NULL")"
                + ", harvest sound \(produce.harvestSound?.description ?? "NULL")"
                + ", seasons \(seasons)"
        }
        if let voiceType = base.voiceType {
            line += ", voice type \(voiceType)"
        }
        if let activateText = base.activateTextOverride {
            line += ", activate text \(displayText(activateText))"
        }
        return line + skippedText(base.skipped)
    }
}
