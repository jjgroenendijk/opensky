// List plumbing for the journal's Quests page. The measured contract is in
// QuestJournalMovieBridge.swift. A list, row, or text field the movie lacks
// answers nil or does nothing: a changed movie leaves a missing-API tally
// entry and an empty readout, never a crash.

import Foundation
import OpenSkyFormatsESM
import OpenSkyFormatsSWF

nonisolated extension QuestJournalMovieBridge {
    // MARK: - Writing

    /// Fills both lists and the two text fields from `model`, then rebuilds the
    /// visible entry clips. The selection is written after `InvalidateData`,
    /// because that call resets `iSelectedIndex` to -1 (measured).
    public static func publish(_ model: JournalMenuModel, runtime: SWFMovieRuntime) {
        rebuild(
            rows: model.entries.map(titleRow),
            atPath: titleListPath,
            selection: model.selectedIndex,
            runtime: runtime
        )
        // The objective list is a readout of the selected quest rather than a
        // second cursor, so it is rebuilt with nothing selected.
        rebuild(
            rows: (model.selectedEntry?.objectives ?? []).map(objectiveRow),
            atPath: objectiveListPath,
            selection: -1,
            runtime: runtime
        )
        publishSelectionText(model, runtime: runtime)
        publishPageFlags(model, runtime: runtime)
    }

    /// Writes one list's rows, rebuilds its entry clips and points it at
    /// `selection`. An empty list is also cleared with `ClearList`, because
    /// `InvalidateData` leaves surplus clips holding the previous rows (measured).
    public static func rebuild(
        rows: [[String: AS2Value]],
        atPath path: String,
        selection: Int,
        runtime: SWFMovieRuntime
    ) {
        publish(rows: rows, atPath: path, runtime: runtime)
        if rows.isEmpty {
            runtime.callMovie(clearMethod, atPath: path, arguments: [])
        }
        invalidate(atPath: path, runtime: runtime)
        select(selection, count: rows.count, atPath: path, runtime: runtime)
    }

    /// The selected quest's name, journal paragraphs and type endpiece.
    public static func publishSelectionText(_ model: JournalMenuModel, runtime: SWFMovieRuntime) {
        let entry = model.selectedEntry
        setText(entry?.title ?? "", atPath: titleTextPath, runtime: runtime)
        setText(entry?.descriptionText ?? "", atPath: descriptionTextPath, runtime: runtime)
        guard let entry else { return }
        runtime.callMovie(
            "gotoAndStop",
            atPath: endpiecesPath,
            arguments: [.string(endpieceFrame(for: entry.kind))]
        )
    }

    /// Replaces one list's `EntriesA` with `rows`.
    public static func publish(
        rows: [[String: AS2Value]],
        atPath path: String,
        runtime: SWFMovieRuntime
    ) {
        MenuMovieEntryList.publish(rows, atPath: path, runtime: runtime)
    }

    /// Rebuilds one list's entry clips from the array just written.
    public static func invalidate(atPath path: String, runtime: SWFMovieRuntime) {
        runtime.callMovie(invalidateMethod, atPath: path, arguments: [])
    }

    /// Points one list at `index`, or at nothing when `index` is negative.
    ///
    /// -1 is the list base's own nothing-selected sentinel, measured on
    /// `iSelectedIndex`, and it is both what an empty list holds and what a
    /// caller asks for when the list is a readout rather than a cursor. A
    /// positive index is clamped into the rows that exist.
    public static func select(
        _ index: Int,
        count: Int,
        atPath path: String,
        runtime: SWFMovieRuntime
    ) {
        guard let list = runtime.node(atPath: path, from: runtime.root) else { return }
        let clamped = count > 0 && index >= 0 ? min(index, count - 1) : -1
        list.object.assign(.integer(clamped), for: selectedIndexName)
    }

    // MARK: - Rows

    /// One quest row. `text` is the field the list base's `SetEntryText` reads;
    /// the rest carry the row's identity back out of a movie-driven selection.
    /// The misc row has the shape the movie's own `onQuestsDataComplete` builds:
    /// FormID 0 and type 0.
    public static func titleRow(_ entry: JournalQuestEntry) -> [String: AS2Value] {
        [
            "text": .string(entry.title),
            "formID": .number(Double(entry.formID.rawValue)),
            "instance": .number(Double(entry.formID.rawValue)),
            "type": .integer(entry.isMiscGroup ? 0 : Int(entry.kind.rawValue)),
            "completed": .boolean(entry.isCompleted),
            "active": .boolean(entry.isTracked)
        ]
    }

    /// One objective row. `completed`, `failed` and `active` are the movie's
    /// own state names, and they move the entry clip off `Normal`. `active`
    /// marks an open objective of a tracked quest; `formID` names that quest.
    public static func objectiveRow(_ objective: JournalObjectiveEntry) -> [String: AS2Value] {
        var row: [String: AS2Value] = [
            "text": .string(objective.text),
            "formID": .number(Double(objective.quest.rawValue)),
            "instance": .integer(Int(objective.index)),
            "completed": .boolean(objective.state == .completed),
            "failed": .boolean(objective.state == .failed),
            "active": .boolean(objective.isActive)
        ]
        // The movie offers "Show on map" only for a row with a target ID.
        if objective.hasTargets, objective.state == .displayed {
            row["questTargetID"] = .number(questTargetID(objective))
        }
        return row
    }

    /// `questTitleEndpieces` frame label for one quest type, from the movie's own
    /// table, which `onQuestHighlight` indexes with the row's `type`. A type the
    /// movie predates falls back to `Misc`.
    public static func endpieceFrame(for kind: Quest.Kind) -> String {
        let index = Int(kind.rawValue)
        return endpieceByType.indices.contains(index) ? endpieceByType[index] : "Misc"
    }

    /// The movie's table, indexed by the QUST `DNAM` type (measured). Misc quests
    /// get the `Favor` frame and side quests `Misc`.
    static let endpieceByType = [
        "Misc", "Main", "MagesGuild", "ThievesGuild", "DarkBrotherhood", "Companion",
        "Favor", "Daedric", "Misc", "CivilWar", "DLC01", "DLC02"
    ]

    /// The endpiece clip's frame labels in timeline order, as measured.
    public static var endpieceFrames: [String] {
        [
            "Main", "MagesGuild", "ThievesGuild", "DarkBrotherhood", "Companion",
            "Favor", "Daedric", "Misc", "CivilWar", "DLC01", "DLC02"
        ]
    }

    // MARK: - Reading

    /// Row `text` values of one list in numeric row order.
    public static func entryLabels(runtime: SWFMovieRuntime, atPath path: String) -> [String] {
        MenuMovieEntryList.labels(atPath: path, runtime: runtime)
    }

    public static func questLabels(runtime: SWFMovieRuntime) -> [String] {
        entryLabels(runtime: runtime, atPath: titleListPath)
    }

    public static func objectiveLabels(runtime: SWFMovieRuntime) -> [String] {
        entryLabels(runtime: runtime, atPath: objectiveListPath)
    }

    public static func selectedIndex(runtime: SWFMovieRuntime, atPath path: String) -> Int? {
        guard
            let list = runtime.node(atPath: path, from: runtime.root),
            case let .number(index) = list.object.lookup(selectedIndexName)?.property.value,
            index.isFinite, index >= 0
        else {
            return nil
        }
        return Int(index)
    }

    /// Text the page's own title field currently holds, which is what proves a
    /// publish reached the movie rather than only the engine model.
    public static func titleText(runtime: SWFMovieRuntime) -> String? {
        text(atPath: titleTextPath, runtime: runtime)
    }

    public static func descriptionText(runtime: SWFMovieRuntime) -> String? {
        text(atPath: descriptionTextPath, runtime: runtime)
    }

    /// The three tallies the bring-up gate reads, for the verification readout.
    public static func diagnostics(runtime: SWFMovieRuntime) -> QuestJournalDiagnostics {
        let tally = runtime.tally
        return QuestJournalDiagnostics(
            faults: tally.faultTotal,
            missingNames: tally.missingNames.count,
            unhandledInvokes: runtime.invokeLog.unhandled
        )
    }

    // MARK: - Text fields

    private static func setText(_ text: String, atPath path: String, runtime: SWFMovieRuntime) {
        guard runtime.node(atPath: path, from: runtime.root) != nil else { return }
        runtime.callMovie("SetText", atPath: path, arguments: [.string(text)])
    }

    private static func text(atPath path: String, runtime: SWFMovieRuntime) -> String? {
        guard let node = runtime.node(atPath: path, from: runtime.root) else { return nil }
        // A field's string is a display *member*, not an entry in the node's
        // property table, so it is read through the runtime rather than off
        // `node.object` the way a list's `EntriesA` is.
        return runtime.text(of: node)
    }

    /// Frame label each visible objective entry clip stops on. It proves a
    /// published row reached the movie, not only the backing array; an
    /// unlabelled frame reports its number. Hidden clips are skipped, because
    /// `ClearList` hides surplus clips and leaves their old labels.
    public static func objectiveEntryFrames(runtime: SWFMovieRuntime) -> [String] {
        guard let list = runtime.node(atPath: objectiveListPath, from: runtime.root) else {
            return []
        }
        return list.children
            .compactMap { child -> (Int, String)? in
                guard
                    let name = child.name, name.hasPrefix("Entry"), child.isVisible,
                    let index = Int(name.dropFirst("Entry".count))
                else {
                    return nil
                }
                let frames = child.timeline?.frames ?? []
                let label = frames.indices.contains(child.currentFrame)
                    ? frames[child.currentFrame].label
                    : nil
                return (index, label ?? "frame \(child.currentFrame + 1)")
            }
            .sorted { $0.0 < $1.0 }
            .map(\.1)
    }
}
