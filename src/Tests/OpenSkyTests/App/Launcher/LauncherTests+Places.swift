// The Launch page's start menu: the settlements by worldspace, a pick, the wait for the
// list, and a saved start the list lacks.

import AppKit
@testable import OpenSky
import OpenSkyFormatsESM
import OpenSkyLaunch
import Testing

extension LauncherTests {
    private static let riverwood = StartPlace(
        start: .marker(worldspace: "Tamriel", plugin: "Skyrim.esm", objectID: 0x900),
        name: "Riverwood", detail: "Skyrim, Town", worldspace: "Skyrim",
        markerType: MapMarkerType(rawValue: 2)
    )
    private static let ravenRock = StartPlace(
        start: .marker(worldspace: "DLC2SolstheimWorld", plugin: "Dragonborn.esm", objectID: 1),
        name: "Raven Rock", detail: "Solstheim, Raven Rock", worldspace: "Solstheim",
        markerType: MapMarkerType(rawValue: 54)
    )
    private static let inn = StartPlace(
        start: .cell("WhiterunInn"), name: "The Bannered Mare", detail: "Interior",
        editorID: "WhiterunInn"
    )
    private static let list = StartPlaceList(
        places: [riverwood, ravenRock, inn], weathers: ["SkyrimClear"]
    )

    @Test func theStartMenuListsTheSettlementsUnderTheirWorldspace() {
        let saved = LaunchPreferences.savedStart()
        defer { LaunchPreferences.remember(saved) }
        LaunchPreferences.remember(.normal)
        let context = LauncherContext(actions: RecordingActions())
        context.startPlaces = Self.list
        let page = LaunchPageViewController(context: context)
        page.loadViewIfNeeded()
        #expect(page.startPopUp.itemTitles == [
            LaunchPageViewController.mainMenuTitle, "", "Skyrim", "Riverwood", "",
            "Solstheim", "Raven Rock"
        ])
        #expect(page.startPopUp.titleOfSelectedItem == LaunchPageViewController.mainMenuTitle)
        page.startPopUp.selectItem(withTitle: "Riverwood")
        page.startPopUp.sendAction(page.startPopUp.action, to: page.startPopUp.target)
        #expect(page.validStart == Self.riverwood.start)
        #expect(LaunchPreferences.savedStart() == Self.riverwood.start)
        #expect(page.playSummary.stringValue.hasSuffix("in Riverwood"))
        #expect(page.startReasonLabel.isHidden)
    }

    @Test func aSavedStartWaitsForTheListAndFallsBackWhenTheListLacksIt() {
        let saved = LaunchPreferences.savedStart()
        defer { LaunchPreferences.remember(saved) }
        LaunchPreferences.remember(Self.inn.start)
        let context = LauncherContext(actions: RecordingActions())
        let page = LaunchPageViewController(context: context)
        page.loadViewIfNeeded()
        #expect(page.validStart == nil)
        #expect(page.startPopUp.titleOfSelectedItem == LaunchPageViewController.readingTitle)
        context.startPlaces = Self.list
        page.refreshPlaces()
        #expect(page.validStart == .normal)
        #expect(page.startPopUp.titleOfSelectedItem == LaunchPageViewController.mainMenuTitle)
        #expect(LaunchPreferences.savedStart() == .normal)
    }
}
