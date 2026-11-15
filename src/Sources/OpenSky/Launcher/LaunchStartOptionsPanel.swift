// The Launch page's options of a new game at a place: the story state and the starting
// items. The game keeps its own hour and weather, and the race menu always opens.

import AppKit
import OpenSkyLaunch

@MainActor
final class LaunchStartOptionsPanel: NSObject {
    let storyPopUp = NSPopUpButton()
    let itemsPopUp = NSPopUpButton()
    let rows: [NSView]

    init(layout: LauncherPageLayout) {
        rows = [layout.row("Story", storyPopUp), layout.row("Starting items", itemsPopUp)]
        super.init()
        configure()
    }

    private func configure() {
        for (popUp, identifier, toolTip) in [
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
        let saved = LaunchPreferences.savedNewGame(at: .normal)
        storyPopUp.selectItem(at: LaunchStory.allCases.firstIndex(of: saved.story) ?? 0)
        itemsPopUp.selectItem(at: LaunchItemPreset.allCases.firstIndex(of: saved.items) ?? 0)
    }

    @objc private func changed() {
        let stories = LaunchStory.allCases
        let presets = LaunchItemPreset.allCases
        guard
            stories.indices.contains(storyPopUp.indexOfSelectedItem),
            presets.indices.contains(itemsPopUp.indexOfSelectedItem)
        else { return }
        LaunchPreferences.remember(
            story: stories[storyPopUp.indexOfSelectedItem],
            items: presets[itemsPopUp.indexOfSelectedItem]
        )
    }
}
