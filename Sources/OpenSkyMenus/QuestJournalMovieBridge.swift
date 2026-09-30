// Vanilla presentation layer for the journal's Quests page: the measured AS2
// contract of the `QuestsPage` half of `Interface\quest_journal.swf`. It rides
// on the System page's bring-up, because both drive the same placed
// `QuestJournalBase`. Measured with `openskycli swf action-run --movie
// quest_journal.swf`; the page shape and frame labels are in
// docs/engine/journal.md.

import Foundation
import OpenSkyFormatsSWF

/// The three tallies a Quests-page bring-up is gated on. Zero of each is the
/// gate passing; the panel and the CLI probe print all three even at zero, so a
/// passing gate cannot be mistaken for a missing readout.
nonisolated public struct QuestJournalDiagnostics: Equatable, Sendable {
    public let faults: Int
    public let missingNames: Int
    public let unhandledInvokes: Int
}

nonisolated public enum QuestJournalMovieBridge: Sendable {
    /// The Quests page is `PageArray[0]`, read off `QuestJournalBase`'s own
    /// `PAGE_QUEST` constant rather than assumed from tab order.
    public static let questsTabIndex = 0
    /// Name of that constant on the registered class, so the index above can be
    /// asserted against the movie instead of trusted.
    public static let questPageConstantName = "PAGE_QUEST"

    public static let moviePath = SystemMenuMovieBridge.moviePath
    public static let menuPath = SystemMenuMovieBridge.menuPath
    public static let questsFaderPath = SystemMenuMovieBridge.questsFaderPath
    public static let pagePath = "\(questsFaderPath)/Page_mc"
    public static let titleListPath = "\(pagePath)/TitleList_mc/List_mc"
    public static let objectiveListPath = "\(pagePath)/objectiveList"
    public static let titleTextPath = "\(pagePath)/questTitleText"
    public static let descriptionTextPath = "\(pagePath)/questDescriptionText"
    public static let endpiecesPath = "\(pagePath)/questTitleEndpieces"

    /// The list base's backing array and selection, shared by both lists.
    public static let entryArrayName = SystemMenuMovieBridge.entryArrayName
    public static let selectedIndexName = "iSelectedIndex"
    /// Method on the list base that rebuilds entry clips from `EntriesA`.
    public static let invalidateMethod = "InvalidateData"
    /// Method on the list base that empties every entry clip.
    public static let clearMethod = "ClearList"

    /// Frame label of a completed objective entry clip, measured off the clip's
    /// own timeline.
    public static let objectiveCompletedFrame = "Completed"

    // MARK: - Bring-up

    /// Brings the Quests page to the front of the already-open journal.
    ///
    /// `SystemMenuMovieBridge.activate(runtime:onClose:)` runs first and owns
    /// the movie's lifecycle calls; this only switches pages, so the two can be
    /// called in either order without the journal opening twice.
    public static func activate(runtime: SWFMovieRuntime) {
        runtime.callMovie(
            "SwitchPageToFront",
            atPath: menuPath,
            arguments: [.integer(questsTabIndex), .boolean(true)]
        )
        showQuestsPage(runtime: runtime)
    }

    /// The tab index the movie's own `QuestJournalBase.PAGE_QUEST` constant
    /// carries, or nil when the class did not register. Used to assert the
    /// pinned `questsTabIndex` against the live movie.
    public static func measuredQuestsTabIndex(runtime: SWFMovieRuntime) -> Int? {
        guard
            let base = runtime.runtime.registeredClass(named: "QuestJournalBase"),
            case let .number(index) = base.lookup(questPageConstantName)?.property.value,
            index.isFinite
        else {
            return nil
        }
        return Int(index)
    }

    /// Whether the Quests page is the one at the front, derived from the
    /// fader's own frame the way the System page's state is.
    public static func isFrontmost(runtime: SWFMovieRuntime) -> Bool {
        guard
            let fader = runtime.node(atPath: questsFaderPath, from: runtime.root),
            let index = fader.timeline?.frameIndex(forLabel: "forceFade")
        else {
            return false
        }
        return fader.currentFrame == index
    }

    // MARK: - Private

    private static func showQuestsPage(runtime: SWFMovieRuntime) {
        if
            let menu = runtime.node(atPath: menuPath, from: runtime.root),
            let page = runtime.node(atPath: pagePath, from: runtime.root),
            let titleList = runtime.node(atPath: titleListPath, from: runtime.root)
        {
            // Same seeding the System page needs: the vanilla host publishes
            // the page and tab index through a tab-button group backed by
            // engine data, which OpenSky has none of.
            menu.object.assign(.object(page.object), for: "TopmostPage")
            menu.object.assign(.integer(questsTabIndex), for: "iCurrentTab")
            runtime.focusTarget = titleList
        }
        for path in [SystemMenuMovieBridge.systemFaderPath, SystemMenuMovieBridge.statsFaderPath] {
            runtime.callMovie("gotoAndStop", atPath: path, arguments: [.string("hide")])
        }
        runtime.callMovie(
            "gotoAndStop",
            atPath: questsFaderPath,
            arguments: [.string("forceFade")]
        )
    }
}
