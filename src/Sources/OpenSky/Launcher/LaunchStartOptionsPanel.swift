// The Launch page's options of a new game at a place: the hour, the weather, the story
// state, the starting items, and the race menu. `LaunchNewGameText` holds the rules;
// this file only shows them.

import AppKit
import OpenSkyLaunch

@MainActor
final class LaunchStartOptionsPanel: NSObject, NSTextFieldDelegate {
    static let gameWeatherTitle = "From the game"

    let hourField = NSTextField()
    let weatherPopUp = NSPopUpButton()
    let storyPopUp = NSPopUpButton()
    let itemsPopUp = NSPopUpButton()
    let raceMenuControl = NSButton(
        checkboxWithTitle: "Open the race menu", target: nil, action: nil
    )
    let hourRow: NSView
    let rows: [NSView]
    var text = LaunchPreferences.savedNewGameText()
    /// Called after a control changed and `text` holds the new values.
    var onChange: () -> Void = {}

    init(layout: LauncherPageLayout) {
        hourRow = layout.row("Hour of the day", hourField)
        rows = [
            hourRow, layout.row("Weather", weatherPopUp), layout.row("Story", storyPopUp),
            layout.row("Starting items", itemsPopUp), layout.toggle(raceMenuControl)
        ]
        super.init()
        configure()
    }

    private func configure() {
        PanelComponents.configureTextField(
            hourField, identifier: "LaunchStartHourControl", width: 60, placeholder: "8"
        )
        hourField.delegate = self
        hourField.toolTip = "The hour of the day, 0 to 24, such as 13.5; empty keeps the game's"
        for (popUp, identifier, toolTip) in [
            (weatherPopUp, "LaunchStartWeatherControl", "The weather forced on arrival"),
            (storyPopUp, "LaunchStartStoryControl", "The state of the main story at the start"),
            (itemsPopUp, "LaunchStartItemsControl", "Items the player gets and wears on arrival")
        ] {
            PanelComponents.configurePopUp(
                popUp, target: self, action: #selector(changed), identifier: identifier
            )
            popUp.toolTip = toolTip
        }
        storyPopUp.addItems(withTitles: LaunchStory.allCases.map(\.title))
        itemsPopUp.addItems(withTitles: LaunchItemPreset.allCases.map(\.title))
        PanelComponents.configureCheckbox(
            raceMenuControl, target: self, action: #selector(changed),
            identifier: "LaunchStartRaceMenuControl"
        )
        raceMenuControl.toolTip = "Off starts as the default character at once"
        refreshWeathers(from: nil)
        show()
    }

    /// The saved weather stays in the menu until the list says the install lacks it.
    func refreshWeathers(from list: StartPlaceList?) {
        var names = list?.weathers ?? []
        let saved = text.weather
        if !saved.isEmpty, !names.contains(saved) {
            if list == nil {
                names.append(saved)
            } else {
                text.weather = ""
                LaunchPreferences.remember(options: text)
            }
        }
        weatherPopUp.removeAllItems()
        weatherPopUp.addItems(withTitles: [Self.gameWeatherTitle] + names)
        weatherPopUp.selectItem(withTitle: text.weather.isEmpty
            ? Self.gameWeatherTitle : text.weather)
    }

    private func show() {
        hourField.stringValue = text.hour
        storyPopUp.selectItem(
            at: LaunchStory.allCases.firstIndex { $0.rawValue == text.story } ?? 0
        )
        itemsPopUp.selectItem(
            at: LaunchItemPreset.allCases.firstIndex { $0.rawValue == text.items } ?? 0
        )
        raceMenuControl.state = text.opensRaceMenu ? .on : .off
    }

    /// The reason the options cannot be used, or nil.
    var problem: LaunchNewGameProblem? {
        if case let .failure(problem) = LaunchNewGameText.hour(from: text.hour) {
            return problem
        }
        return nil
    }

    private func read() {
        text.hour = hourField.stringValue
        let weather = weatherPopUp.titleOfSelectedItem ?? Self.gameWeatherTitle
        text.weather = weather == Self.gameWeatherTitle ? "" : weather
        let stories = LaunchStory.allCases
        let presets = LaunchItemPreset.allCases
        if stories.indices.contains(storyPopUp.indexOfSelectedItem) {
            text.story = stories[storyPopUp.indexOfSelectedItem].rawValue
        }
        if presets.indices.contains(itemsPopUp.indexOfSelectedItem) {
            text.items = presets[itemsPopUp.indexOfSelectedItem].rawValue
        }
        text.opensRaceMenu = raceMenuControl.state == .on
        if problem == nil {
            LaunchPreferences.remember(options: text)
        }
    }

    func controlTextDidChange(_: Notification) {
        changed()
    }

    @objc private func changed() {
        read()
        onChange()
    }
}
