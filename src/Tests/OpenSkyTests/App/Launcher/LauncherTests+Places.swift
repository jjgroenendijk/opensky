// The Launch page's place start: a pick from the list, its options, and a lost place.

import AppKit
@testable import OpenSky
import OpenSkyGameData
import OpenSkyLaunch
import Testing

extension LauncherTests {
    @Test func aPlaceFromTheListStartsANewGameThereUntilTheLoadOrderLosesIt() {
        let settings = SettingsStore(defaults: GameDataLocator.settingsDefaults)
        let saved = LaunchPreferences.savedStart()
        let recent = settings.value(LaunchPreferences.recentPlacesSetting)
        defer {
            LaunchPreferences.remember(saved)
            settings.set(recent, for: LaunchPreferences.recentPlacesSetting)
        }
        let inn = StartPlace(
            start: .cell("WhiterunInn"), name: "The Bannered Mare", detail: "Interior",
            editorID: "WhiterunInn"
        )
        let list = StartPlaceList(places: [inn], weathers: ["SkyrimClear"])
        let context = LauncherContext(actions: RecordingActions())
        context.startPlaces = list
        let page = LaunchPageViewController(context: context)
        page.loadViewIfNeeded()
        page.pick(inn)
        #expect(page.validStart == .cell("WhiterunInn"))
        #expect(page.placeName(of: inn.start) == "The Bannered Mare")
        #expect(!page.startPlaceRow.isHidden)
        #expect(!page.startOptions.hourRow.isHidden)
        #expect(page.startOptions.weatherPopUp.itemTitles.contains("SkyrimClear"))
        #expect(LaunchPreferences.savedRecentPlaces().first?.start == inn.start)
        page.startOptions.hourField.stringValue = "30"
        page.startOptions
            .controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        #expect(page.startReasonLabel.stringValue.contains("hour"))
        page.startOptions.hourField.stringValue = ""
        page.startOptions
            .controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        #expect(page.startReasonLabel.isHidden)
        context.startPlaces = .empty
        page.refreshPlaces()
        #expect(page.validStart == nil)
        #expect(page.startReasonLabel.stringValue.contains("The Bannered Mare"))
        var picked: [StartPlace] = []
        let picker = StartPlacePickerViewController(
            list: list, recent: [LaunchRecentPlace(start: inn.start, name: inn.name)]
        ) { picked.append($0) }
        picker.loadViewIfNeeded()
        #expect(picker.rows == [inn])
        picker.show(query: "nowhere")
        #expect(picker.rows.isEmpty)
        #expect(picked.isEmpty)
    }
}
