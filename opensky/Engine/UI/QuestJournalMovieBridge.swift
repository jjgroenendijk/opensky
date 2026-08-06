// Vanilla presentation layer for the journal's Quests page (issue #184,
// roadmap item 13.5): the measured AS2 contract of the `QuestsPage` half of
// `Interface\quest_journal.swf`.
//
// A satellite of UI/SystemMenuMovieBridge.swift rather than a second movie
// bring-up. Both drive the same placed `QuestJournalBase`, so the System page's
// `prepare(runtime:)` registration is the one that runs and this file adds only
// what the Quests page itself reaches for. `docs/decisions/swf-as2-scope.md`
// named this the deferred phase-4 contract that "lands in the milestone that
// owns its data"; M13 owns it.
//
// Everything below was measured with `openskycli swf action-run --movie
// quest_journal.swf`, whose `--dump`, `--dump-class` and `--dump-proto` options
// print the page instance, the registered `QuestsPage` class and the list
// widgets' prototype chains. Nothing is taken from memory of the shipped game.
//
// Measured shape of the page (`.../QuestsFader/Page_mc`, class `QuestsPage`):
//
//   TitleList_mc/List_mc   class `QuestTitleList`; the quest rows
//   objectiveList          class `ObjectiveScrollingList`; the selected
//                          quest's objectives
//   questTitleText         the selected quest's name
//   questDescriptionText   the selected quest's journal paragraphs
//   questTitleEndpieces    a decorative clip whose frame labels are the quest
//                          types: Main, MagesGuild, ThievesGuild,
//                          DarkBrotherhood, Companion, Favor, Daedric, Misc,
//                          CivilWar, DLC01, DLC02
//   NoQuestsText           shown instead of a list when there is nothing
//
// Both lists inherit the same list base: `EntriesA` holds the rows, the
// `entryList` property is its accessor, `iSelectedIndex` holds the selection
// with -1 for none, and `InvalidateData()` rebuilds the visible entry clips
// from the array. The objective entry clips carry the frame labels `Normal`,
// `NormalSelected`, `Completed`, `CompletedSelected`, `Failed`,
// `FailedSelected`, `Active`, `ActiveSelected` and `None`, which is the
// display-state vocabulary the page draws objectives with.
//
// Documented in docs/engine/journal.md.

import Foundation

/// The three tallies a Quests-page bring-up is gated on. Zero of each is the
/// gate passing; the panel and the CLI probe print all three even at zero, so a
/// passing gate cannot be mistaken for a missing readout.
nonisolated struct QuestJournalDiagnostics: Equatable, Sendable {
    let faults: Int
    let missingNames: Int
    let unhandledInvokes: Int
}

nonisolated enum QuestJournalMovieBridge {
    /// The Quests page is `PageArray[0]`, read off `QuestJournalBase`'s own
    /// `PAGE_QUEST` constant rather than assumed from tab order.
    static let questsTabIndex = 0
    /// Name of that constant on the registered class, so the index above can be
    /// asserted against the movie instead of trusted.
    static let questPageConstantName = "PAGE_QUEST"

    static let moviePath = SystemMenuMovieBridge.moviePath
    static let menuPath = SystemMenuMovieBridge.menuPath
    static let questsFaderPath = SystemMenuMovieBridge.questsFaderPath
    static let pagePath = "\(questsFaderPath)/Page_mc"
    static let titleListPath = "\(pagePath)/TitleList_mc/List_mc"
    static let objectiveListPath = "\(pagePath)/objectiveList"
    static let titleTextPath = "\(pagePath)/questTitleText"
    static let descriptionTextPath = "\(pagePath)/questDescriptionText"
    static let noQuestsTextPath = "\(pagePath)/NoQuestsText"
    static let endpiecesPath = "\(pagePath)/questTitleEndpieces"

    /// The list base's backing array and selection, shared by both lists.
    static let entryArrayName = SystemMenuMovieBridge.entryArrayName
    static let selectedIndexName = "iSelectedIndex"
    /// Method on the list base that rebuilds entry clips from `EntriesA`.
    static let invalidateMethod = "InvalidateData"
    /// Method on the list base that empties every entry clip.
    static let clearMethod = "ClearList"

    /// Frame labels of an objective entry clip, measured off the clip's own
    /// timeline. `Active` marks the player's tracked objective, which OpenSky
    /// does not model yet, so it is listed but never selected.
    static let objectiveNormalFrame = "Normal"
    static let objectiveCompletedFrame = "Completed"
    static let objectiveFailedFrame = "Failed"

    // MARK: - Bring-up

    /// Brings the Quests page to the front of the already-open journal.
    ///
    /// `SystemMenuMovieBridge.activate(runtime:onClose:)` runs first and owns
    /// the movie's lifecycle calls; this only switches pages, so the two can be
    /// called in either order without the journal opening twice.
    static func activate(runtime: SWFMovieRuntime) {
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
    static func measuredQuestsTabIndex(runtime: SWFMovieRuntime) -> Int? {
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
    static func isFrontmost(runtime: SWFMovieRuntime) -> Bool {
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
