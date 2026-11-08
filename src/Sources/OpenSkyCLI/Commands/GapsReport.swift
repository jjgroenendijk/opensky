// The `gaps` report: one section per area, each with how much is done, what is
// left ranked by how often the data uses it, and a summary table on top.

import Foundation
import OpenSkyFormatsCore

struct GapRow {
    let name: String
    /// How often the data uses it: call sites, conditions, records, effects.
    let uses: Int
}

struct GapSection {
    let title: String
    /// What one item is, plural: "natives", "functions".
    let unit: String
    /// Distinct items done, or nil when the area has no countable whole.
    let done: Int?
    let left: [GapRow]
    /// What the uses count, plural: "call sites".
    let usesUnit: String
    var notes: [String] = []

    var total: Int? {
        done.map { $0 + left.count }
    }

    var percentDone: String {
        guard let done, let total, total > 0 else { return "-" }
        return "\(done * 100 / total)%"
    }

    init(
        title: String,
        unit: String,
        done: Int?,
        left: [(name: String, count: Int)],
        usesUnit: String,
        notes: [String] = []
    ) {
        self.title = title
        self.unit = unit
        self.done = done
        self.left = left.map { GapRow(name: $0.name, uses: $0.count) }
        self.usesUnit = usesUnit
        self.notes = notes
    }
}

extension GapSection {
    /// Done and left from what a census counted: `handled` decides each item.
    init(
        title: String,
        unit: String,
        counts: GapCounts,
        handled: (String) -> Bool,
        usesUnit: String,
        notes: [String] = []
    ) {
        self.init(
            title: title,
            unit: unit,
            done: counts.done(where: handled),
            left: counts.left(where: handled),
            usesUnit: usesUnit,
            notes: notes
        )
    }

    /// A list with no whole to count against, such as decode failures.
    init(title: String, unit: String, failures: GapCounts, usesUnit: String, notes: [String] = []) {
        self.init(
            title: title,
            unit: unit,
            done: nil,
            left: GapCounts.ranked(failures.uses),
            usesUnit: usesUnit,
            notes: notes
        )
    }
}

enum GapsReport {
    static func summary(_ sections: [GapSection]) -> [String] {
        let width = max(24, sections.map(\.title.count).max() ?? 0)
        var lines = ["[INFO] gaps summary: done and left per area, counted in distinct items"]
        lines
            .append(pad("area", width) + pad("done", 8) + pad("left", 8) + pad("total", 8) +
                "done %")
        for section in sections {
            lines.append(
                pad(section.title, width) + pad(section.done.map(String.init) ?? "-", 8)
                    + pad(String(section.left.count), 8)
                    + pad(section.total.map(String.init) ?? "-", 8) + section.percentDone
            )
        }
        return lines
    }

    /// The summary as a Markdown table, for the README.
    static func markdownSummary(_ sections: [GapSection]) -> [String] {
        ["| Area | Done | Left | Total | Done % |", "| --- | --: | --: | --: | --: |"]
            + sections.map { section in
                "| \(section.title) | \(section.done.map(String.init) ?? "-") "
                    + "| \(section.left.count) | \(section.total.map(String.init) ?? "-") "
                    + "| \(section.percentDone) |"
            }
    }

    static func lines(_ section: GapSection, limit: Int?) -> [String] {
        let leftUses = section.left.reduce(0) { $0 + $1.uses }
        var lines = ["", "== \(section.title)"]
        if let done = section.done, let total = section.total {
            lines.append(
                "[INFO] \(done) of \(total) \(section.unit) done (\(section.percentDone)), "
                    + "\(section.left.count) left, used by \(leftUses) \(section.usesUnit)"
            )
        } else {
            lines.append(
                "[INFO] \(section.left.count) \(section.unit) left, "
                    + "used by \(leftUses) \(section.usesUnit)"
            )
        }
        lines += section.notes.map { "[INFO] \($0)" }
        let shown = limit.map { Array(section.left.prefix($0)) } ?? section.left
        lines += shown.map { "  " + pad(String($0.uses), 9) + $0.name }
        if shown.count < section.left.count {
            lines.append("  ... \(section.left.count - shown.count) more")
        }
        return lines
    }

    private static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text + " " : text + String(repeating: " ", count: width - text.count)
    }
}
