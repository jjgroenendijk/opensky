// HUD & Interaction > Menu screens with the provider fake: pinned ids, the open
// button driving the fake, and the readout lines.

import AppKit
@testable import OpenSky
import OpenSkyMenus
import Testing

@MainActor
struct MenuScreensPanelTests {
    private func section(_ provider: FakeWorldProviders) -> MenuScreensSection {
        let panel = HUDInteractionPanelViewController()
        panel.loadViewIfNeeded()
        panel.menuScreensProvider = provider
        return panel.menuScreensSection
    }

    @Test func accessibilityIdentifiersArePinned() {
        let section = section(FakeWorldProviders())
        #expect(section.sectionIdentifier == "menuScreens")
        #expect(section.screenControl.accessibilityIdentifier() == "MenuScreenSelectControl")
        #expect(section.openControl.accessibilityIdentifier() == "MenuScreenOpenControl")
    }

    @Test func openButtonOpensTheChosenScreen() {
        let provider = FakeWorldProviders()
        let section = section(provider)
        section.screenControl.selectItem(withTitle: "Crafting")
        section.openControl.sendAction(section.openControl.action, to: section.openControl.target)
        #expect(provider.presentationState.openedScreens == [.crafting])
    }

    @Test func readoutListsEachScreen() {
        let provider = FakeWorldProviders()
        provider.presentationState.menuScreenReadouts = [
            MenuScreenReadout(kind: .wait, state: "movie", lastResult: "Waited 3 h")
        ]
        let section = section(provider)
        section.refreshReadout()
        #expect(section.readout == "Wait: movie, Waited 3 h")
    }
}
