// Everything the save inspector and `openskycli ess` show for one `.ess`, as text
// sections: header, plugins against the current load order, section sizes, global
// tables, change form histograms, Papyrus counts, and a dry-run import report.

import Foundation
import OpenSkyFormatsESS

nonisolated public struct ESSInspectionSection: Equatable, Sendable {
    public let title: String
    public let lines: [String]
}

nonisolated public struct ESSInspection: Sendable {
    public let file: ESSFile
    public let survey: ESSChangeFormSurvey
    public let loadOrder: ESSLoadOrderComparison
    /// Change form ids by ref id kind.
    public let refIDKinds: [ESSRefID.Kind: Int]
    public let papyrus: Result<ESSPapyrus?, ESSError>
    /// Nil when no load order was given, so no import could run.
    public let report: ESSImportReport?

    /// `records` adds the dry-run import report; nothing is applied.
    public init(file: ESSFile, currentPlugins: [String], records: (any ESSImportRecords)? = nil) {
        self.file = file
        survey = ESSChangeFormSurvey(file.changeForms)
        loadOrder = ESSLoadOrderComparison(
            savePlugins: file.plugins + file.lightPlugins, currentPlugins: currentPlugins
        )
        var kinds: [ESSRefID.Kind: Int] = [:]
        for form in file.changeForms {
            kinds[form.form.kind, default: 0] += 1
        }
        refIDKinds = kinds
        do throws(ESSError) {
            papyrus = try .success(file.papyrus())
        } catch {
            papyrus = .failure(error)
        }
        report = records.map { ESSImporter.run(file, records: $0, appVersion: "inspector").report }
    }

    public var sections: [ESSInspectionSection] {
        [
            ESSInspectionSection(title: "Header", lines: headerLines),
            ESSInspectionSection(title: "Plugins", lines: pluginLines),
            ESSInspectionSection(title: "Sections", lines: sectionLines),
            ESSInspectionSection(title: "Global data", lines: globalLines),
            ESSInspectionSection(title: "Change forms", lines: changeFormLines),
            ESSInspectionSection(title: "Papyrus", lines: papyrusLines),
            ESSInspectionSection(title: "Import report", lines: report?.lines ?? ["no load order"])
        ]
    }

    public var text: String {
        sections.map { section in
            (["== \(section.title)"] + section.lines).joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    private var headerLines: [String] {
        let header = file.header
        return [
            "version \(header.version), form version \(file.formVersion), "
                + "compression \(header.compression.name)",
            "\(header.playerName), level \(header.playerLevel), \(header.playerRaceEditorID), "
                + (header.isFemale ? "female" : "male"),
            "\(header.playerLocation), \(header.gameDate)",
            "save \(header.saveNumber), "
                + "screenshot \(header.screenshotWidth)x\(header.screenshotHeight)",
            String(
                format: "experience %.1f of %.1f", header.experience, header.experienceForNextLevel
            )
        ]
    }

    private var pluginLines: [String] {
        var lines = loadOrder.rows.map { row in
            let now = row.currentPosition.map { "loaded at \($0)" } ?? "NOT LOADED"
            return "\(row.savePosition): \(row.name) - \(now)"
        }
        if !loadOrder.added.isEmpty {
            lines.append("loaded now, not in the save: \(loadOrder.added.joined(separator: ", "))")
        }
        lines.append(loadOrder.isReordered ? "order differs from now" : "order matches")
        return lines
    }

    private var sectionLines: [String] {
        let counts = file.locationTable.counts
        return [
            "body \(file.bodyLength) bytes, offsets count from \(file.offsetBase) "
                + "(file body at \(file.expectedOffsetBase))",
            "global data: \(counts.globalData1) + \(counts.globalData2) + "
                + "\(file.globalData3.count) tables (table 3 count says \(counts.globalData3))",
            "change forms: \(counts.changeForms)",
            "form id array: \(file.formIDArray.count), visited worldspaces: "
                + "\(file.visitedWorldspaces.count)",
            "ref id kinds: " + ESSRefID.Kind.allCases.map {
                "\($0.name) \(refIDKinds[$0] ?? 0)"
            }.joined(separator: ", ")
        ]
    }

    private var globalLines: [String] {
        file.globalData.map { "\(ESSGlobalDataType.name(of: $0.type)): \($0.data.count) bytes" }
    }

    private var changeFormLines: [String] {
        survey.types.map { row in
            var line = "\(row.signature): \(row.count)"
            if row.hasDecoder {
                line += ", \(row.complete) complete"
            }
            let flags = row.flags.sorted { $0.key < $1.key }.map {
                "\(ESSChangeFlag.name(of: $0.key, type: row.signature)) \($0.value)"
            }
            let blocked = row.blocked.sorted { $0.key < $1.key }
                .map { "blocked by \($0.key) \($0.value)" }
            let failed = row.failed.sorted { $0.key < $1.key }
                .map { "failed \($0.key) \($0.value)" }
            return ([line] + flags + blocked + failed).joined(separator: "; ")
        }
    }

    private var papyrusLines: [String] {
        switch papyrus {
        case let .failure(error):
            return ["not decoded: \(error)"]
        case .success(nil):
            return ["no Papyrus table"]
        case let .success(papyrus?):
            let variables = papyrus.instances.reduce(0) { $0 + $1.variables.count }
            return [
                "\(papyrus.strings.count) strings, \(papyrus.scripts.count) scripts, "
                    + "\(papyrus.idWidth)-byte ids",
                "\(papyrus.instances.count) instances with \(variables) variables",
                "\(papyrus.references.count) references, \(papyrus.arrays.count) arrays",
                "\(papyrus.activeScripts.count) active stacks, "
                    + "\(papyrus.suspendedStacks.count) suspended",
                "stacks: " + (papyrus.stackStatus.blockedBy ?? "read")
            ]
        }
    }
}
