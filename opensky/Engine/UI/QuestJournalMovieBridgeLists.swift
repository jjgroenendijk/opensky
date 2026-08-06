// List plumbing for the journal's Quests page (issue #184). Satellite of
// UI/QuestJournalMovieBridge.swift, which holds the measured contract.
//
// Same degradation rule as every other movie bridge: a list the movie has not
// built, a row that is not an object, a text field that is not there — each
// answers nil or does nothing. A vanilla movie whose shape moved must leave an
// entry in the missing-API tally and an empty readout, never take the app down.

import Foundation

nonisolated extension QuestJournalMovieBridge {
    // MARK: - Writing

    /// Fills both lists and the two text fields from `model`, then rebuilds the
    /// visible entry clips.
    ///
    /// Order matters and was measured: `InvalidateData` rebuilds from the array
    /// and resets `iSelectedIndex` to the list base's own nothing-selected
    /// sentinel of -1 as it goes, so the selection is written afterwards, not
    /// before, exactly as the inventory menu's list does.
    static func publish(_ model: JournalMenuModel, runtime: SWFMovieRuntime) {
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
    }

    /// Writes one list's rows, rebuilds its entry clips and points it at
    /// `selection`.
    ///
    /// A list that ends up empty is cleared rather than only invalidated:
    /// measured, `InvalidateData` rebuilds as many clips as there are rows and
    /// leaves the rest holding whatever the previous publish put there, so a
    /// quest with no objectives would keep showing the last quest's first line.
    /// `ClearList` is the base class's own method for exactly that.
    static func rebuild(
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
    static func publishSelectionText(_ model: JournalMenuModel, runtime: SWFMovieRuntime) {
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
    static func publish(
        rows: [[String: AS2Value]],
        atPath path: String,
        runtime: SWFMovieRuntime
    ) {
        guard let list = runtime.node(atPath: path, from: runtime.root) else { return }
        let entries = runtime.runtime.makeArray(
            rows.map { fields in
                let row = runtime.runtime.makeObject()
                // Sorted so two publishes of equal rows build identical
                // objects, which is what makes a published list comparable.
                for name in fields.keys.sorted() {
                    row.assign(fields[name] ?? .undefined, for: name)
                }
                return .object(row)
            }
        )
        list.object.assign(.object(entries), for: entryArrayName)
    }

    /// Rebuilds one list's entry clips from the array just written.
    static func invalidate(atPath path: String, runtime: SWFMovieRuntime) {
        runtime.callMovie(invalidateMethod, atPath: path, arguments: [])
    }

    /// Points one list at `index`, or at nothing when `index` is negative.
    ///
    /// -1 is the list base's own nothing-selected sentinel, measured on
    /// `iSelectedIndex`, and it is both what an empty list holds and what a
    /// caller asks for when the list is a readout rather than a cursor. A
    /// positive index is clamped into the rows that exist.
    static func select(
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
    static func titleRow(_ entry: JournalQuestEntry) -> [String: AS2Value] {
        [
            "text": .string(entry.title),
            "formID": .number(Double(entry.formID.rawValue)),
            "instance": .number(Double(entry.formID.rawValue)),
            "type": .integer(endpieceFrameIndex(for: entry.kind)),
            "completed": .boolean(entry.isCompleted),
            "active": .boolean(false)
        ]
    }

    /// One objective row.
    ///
    /// `completed`, `failed` and `active` are the three names the movie's own
    /// action side carries for an objective's state, and driving them is what
    /// moves the entry clip off `Normal` — see the frame readout of
    /// `openskycli swf quest-journal --objective-state completed`. `active`
    /// marks the player's tracked objective, which OpenSky does not model, so
    /// it is published false rather than guessed.
    static func objectiveRow(_ objective: JournalObjectiveEntry) -> [String: AS2Value] {
        [
            "text": .string(objective.text),
            "instance": .integer(Int(objective.index)),
            "completed": .boolean(objective.state == .completed),
            "failed": .boolean(objective.state == .failed),
            "active": .boolean(false)
        ]
    }

    /// Entry-clip frame label for one objective display state.
    static func frameLabel(for state: JournalObjectiveEntry.State) -> String {
        switch state {
        case .displayed: objectiveNormalFrame
        case .completed: objectiveCompletedFrame
        case .failed: objectiveFailedFrame
        }
    }

    /// `questTitleEndpieces` frame label for one quest type. The clip's own
    /// labels are the type names, so the mapping is a rename rather than a
    /// number: the movie has no endpiece for a type it predates, which falls
    /// back to `Misc`.
    static func endpieceFrame(for kind: Quest.Kind) -> String {
        switch kind {
        case .mainQuest: "Main"
        case .magesGuild: "MagesGuild"
        case .thievesGuild: "ThievesGuild"
        case .darkBrotherhood: "DarkBrotherhood"
        case .companionQuests: "Companion"
        case .sideQuests: "Favor"
        case .daedricQuests: "Daedric"
        case .civilWar: "CivilWar"
        case .vampire: "DLC01"
        case .dragonborn: "DLC02"
        case .none, .miscellaneous, .unknown: "Misc"
        }
    }

    /// Position of that label in the clip's own label order, which is the
    /// number a row carries when the page wants the type without the name.
    static func endpieceFrameIndex(for kind: Quest.Kind) -> Int {
        endpieceFrames.firstIndex(of: endpieceFrame(for: kind)) ?? 0
    }

    /// The endpiece clip's frame labels in timeline order, as measured.
    static var endpieceFrames: [String] {
        [
            "Main", "MagesGuild", "ThievesGuild", "DarkBrotherhood", "Companion",
            "Favor", "Daedric", "Misc", "CivilWar", "DLC01", "DLC02"
        ]
    }

    // MARK: - Reading

    /// Row `text` values of one list in numeric row order.
    ///
    /// `EntriesA` is an AS2 array, so its rows are numeric property names and
    /// have to be sorted numerically — lexical order puts row 10 before row 2.
    static func entryLabels(runtime: SWFMovieRuntime, atPath path: String) -> [String] {
        guard
            let list = runtime.node(atPath: path, from: runtime.root),
            let entries = list.object.lookup(entryArrayName)?.property.value.objectValue
        else {
            return []
        }
        return entries.ownPropertyNames
            .compactMap { name in Int(name).map { ($0, name) } }
            .sorted { $0.0 < $1.0 }
            .compactMap { _, name in
                guard
                    let row = entries.lookup(name)?.property.value.objectValue,
                    case let .string(text) = row.lookup("text")?.property.value
                else {
                    return nil
                }
                return text
            }
    }

    static func questLabels(runtime: SWFMovieRuntime) -> [String] {
        entryLabels(runtime: runtime, atPath: titleListPath)
    }

    static func objectiveLabels(runtime: SWFMovieRuntime) -> [String] {
        entryLabels(runtime: runtime, atPath: objectiveListPath)
    }

    static func selectedIndex(runtime: SWFMovieRuntime, atPath path: String) -> Int? {
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
    static func titleText(runtime: SWFMovieRuntime) -> String? {
        text(atPath: titleTextPath, runtime: runtime)
    }

    static func descriptionText(runtime: SWFMovieRuntime) -> String? {
        text(atPath: descriptionTextPath, runtime: runtime)
    }

    /// The three tallies the bring-up gate reads, for the verification readout.
    static func diagnostics(runtime: SWFMovieRuntime) -> QuestJournalDiagnostics {
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

    /// Frame label each *visible* objective entry clip currently stops on.
    ///
    /// The page's own display-state readout: `ObjectiveScrollingList.SetEntry`
    /// moves the clip to one of the labels measured on its timeline, so this is
    /// what proves a published objective row reached the movie and not only the
    /// backing array. A clip stopped on an unlabelled frame reports its number.
    ///
    /// Hidden clips are left out because that is how the list retires a row:
    /// `ClearList` hides the surplus entry clips rather than moving them back
    /// to a blank frame, so a cleared list still holds the last row's label on
    /// a clip nobody can see.
    static func objectiveEntryFrames(runtime: SWFMovieRuntime) -> [String] {
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
