// The two data requests of the journal's Quests page. The movie asks for the
// quest rows when the page starts and for a quest's objectives when it is
// highlighted, then lays out the page itself. See docs/engine/journal.md.

import Foundation
public import OpenSkyFormatsESM
public import OpenSkyFormatsSWF

nonisolated extension QuestJournalMovieBridge {
    public static let questsDataCall = "RequestQuestsData"
    public static let objectivesDataCall = "RequestObjectivesData"

    /// Answers both requests from `model`, read at the time of each call.
    public static func registerRequests(
        runtime: SWFMovieRuntime,
        model: @escaping @MainActor @Sendable () -> JournalMenuModel
    ) {
        runtime.registerHostFunction(questsDataCall) { call in
            guard case let .object(list) = call.arguments.first else {
                call.movie.runtime.noteMissing(questsDataCall)
                return nil
            }
            let model = MainActor.assumeIsolated { model() }
            MenuMovieEntryList.fill(list, with: questRows(model), runtime: call.movie)
            call.respond(questsDataAnswer(model))
            return nil
        }
        runtime.registerHostFunction(objectivesDataCall) { call in
            let model = MainActor.assumeIsolated { model() }
            fillObjectives(model, runtime: call.movie)
            return nil
        }
    }

    /// The rows `RequestQuestsData` fills in. The misc group is left out,
    /// because `onQuestsDataComplete` adds its own `$MISCELLANEOUS` row.
    public static func questRows(_ model: JournalMenuModel) -> [[String: AS2Value]] {
        model.entries.filter { !$0.isMiscGroup }.map { entry in
            var row = titleRow(entry)
            row["description"] = .string(entry.descriptionText)
            return row
        }
    }

    /// `onQuestsDataComplete(savedFormID, savedInstance, addMiscRow,
    /// miscRowActive, allowShowOnMap)`. The saved quest is the one the movie
    /// selects and scrolls to.
    public static func questsDataAnswer(_ model: JournalMenuModel) -> [AS2Value] {
        let misc = model.entries.first(where: \.isMiscGroup)
        let saved = model.selectedEntry.map { Double($0.formID.rawValue) } ?? -1
        return [
            .number(saved), .number(saved), .boolean(misc != nil),
            .boolean(misc?.isTracked ?? false), .boolean(true)
        ]
    }

    /// Writes `objectives` onto the title list's selected row, which
    /// `onQuestHighlight` reads straight after the call.
    static func fillObjectives(_ model: JournalMenuModel, runtime: SWFMovieRuntime) {
        guard
            let list = runtime.node(atPath: titleListPath, from: runtime.root),
            let index = selectedIndex(runtime: runtime, atPath: titleListPath),
            let row = MenuMovieEntryList.row(at: index, of: list.object),
            let quest = movieQuest(row)
        else {
            runtime.runtime.noteMissing(objectivesDataCall)
            return
        }
        let entry = model.entries.first { $0.formID == quest }
        let rows = (entry?.objectives ?? []).map(objectiveRow)
        row.assign(.object(MenuMovieEntryList.makeArray(rows, runtime: runtime)), for: "objectives")
    }

    /// The quest of the title list's selected row: FormID 0 is the misc row.
    /// Nil when nothing is selected or the row is the divider.
    public static func selectedQuest(runtime: SWFMovieRuntime) -> FormID? {
        guard
            let list = runtime.node(atPath: titleListPath, from: runtime.root),
            let index = selectedIndex(runtime: runtime, atPath: titleListPath),
            let row = MenuMovieEntryList.row(at: index, of: list.object)
        else {
            return nil
        }
        return movieQuest(row)
    }

    private static func movieQuest(_ row: AS2Object) -> FormID? {
        guard
            case let .number(number) = row.lookup("formID")?.property.value,
            number >= 0, number <= Double(UInt32.max)
        else {
            return nil
        }
        return FormID(UInt32(number))
    }

    /// Starts the Quests page as a tab change does: the page asks for its rows.
    public static func startQuestsPage(runtime: SWFMovieRuntime) {
        runtime.callMovie("startPage", atPath: pagePath)
    }

    /// Shows `model` as a fresh page start. `bUpdated` is cleared first,
    /// because `startPage` asks for the rows only once per open.
    public static func show(_ model: JournalMenuModel, runtime: SWFMovieRuntime) {
        registerRequests(runtime: runtime) { model }
        runtime.node(atPath: pagePath, from: runtime.root)?.object
            .assign(.boolean(false), for: "bUpdated")
        startQuestsPage(runtime: runtime)
    }
}
