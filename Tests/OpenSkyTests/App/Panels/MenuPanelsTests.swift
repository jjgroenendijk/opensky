// World > Character and World > Map: stable ids, buttons that reach the
// provider, enablement that follows the menu, and the readouts.

import AppKit
@testable import OpenSky
@testable import OpenSkyMenus
import Testing

struct MenuPanelsTests {
    @MainActor
    private func send(_ control: NSControl) {
        control.sendAction(control.action, to: control.target)
    }

    @Test @MainActor
    func characterPanelPinsIdsAndDrivesTheMenus() {
        let provider = FakeWorldProviders()
        let panel = CharacterMenuPanelViewController()
        panel.provider = provider
        panel.loadViewIfNeeded()
        #expect(panel.titleSection.sectionIdentifier == "titleMenu")
        #expect(panel.raceSection.sectionIdentifier == "raceMenu")
        #expect(panel.titleSection.buttons.map { $0.accessibilityIdentifier() } == [
            "TitleMenuOpenControl", "TitleMenuUpControl", "TitleMenuDownControl",
            "TitleMenuChooseControl", "TitleMenuMovieControl"
        ])
        send(panel.titleSection.buttons[4])
        #expect(provider.menuCalls.calls == ["title.movie(false)"])
        provider.menuCalls.calls = []
        #expect(panel.raceSection.buttons.map { $0.accessibilityIdentifier() } == [
            "RaceMenuOpenControl", "RaceMenuOpenLimitedControl", "RaceMenuResetControl",
            "RaceMenuUpControl", "RaceMenuDownControl", "RaceMenuLeftControl",
            "RaceMenuRightControl", "RaceMenuDoneControl"
        ])
        #expect(panel.raceSection.nameControl.accessibilityIdentifier() == "RaceMenuNameControl")
        panel.raceSection.refreshReadout()
        #expect(!panel.raceSection.buttons[3].isEnabled, "Up waits for an open menu")
        send(panel.raceSection.buttons[2])
        send(panel.raceSection.buttons[1])
        #expect(provider.menuCalls.calls == ["race.reset", "race.open(true)"])
        panel.raceSection.refreshReadout()
        #expect(panel.raceSection.buttons[3].isEnabled)
        #expect(!panel.raceSection.buttons[2].isEnabled, "Reset waits for a closed menu")
        panel.raceSection.nameControl.stringValue = "Ada"
        send(panel.raceSection.nameControl)
        #expect(provider.menuCalls.calls.last == "race.name(Ada)")
        #expect(DestinationRegistry.characterMenuOverrides.isOverridden(
            WorldPanelContext(providers: provider)
        ))
        DestinationRegistry.characterMenuOverrides.resetToDefaults(
            WorldPanelContext(providers: provider)
        )
        #expect(!provider.menuCalls.raceOpen)
    }

    @Test @MainActor
    func mapPanelPinsIdsAndOpensAndCloses() {
        let provider = FakeWorldProviders()
        let panel = MapMenuPanelViewController()
        panel.provider = provider
        panel.loadViewIfNeeded()
        #expect(panel.mapSection.sectionIdentifier == "mapMenu")
        #expect(panel.mapSection.buttons.map { $0.accessibilityIdentifier() } == [
            "MapMenuOpenWorldControl", "MapMenuOpenLocalControl", "MapMenuCloseControl",
            "MapMenuNorthControl", "MapMenuSouthControl", "MapMenuWestControl",
            "MapMenuEastControl", "MapMenuZoomInControl", "MapMenuZoomOutControl",
            "MapMenuTiltControl", "MapMenuTravelControl", "MapMenuRevealAllControl",
            "MapMenuResetFogControl"
        ])
        panel.mapSection.refreshReadout()
        #expect(panel.mapSection.buttons[11].isEnabled, "reveal works with the map closed")
        send(panel.mapSection.buttons[11])
        send(panel.mapSection.buttons[12])
        send(panel.mapSection.buttons[0])
        send(panel.mapSection.buttons[7])
        #expect(provider.menuCalls.calls == [
            "map.revealAll", "map.resetFog", "map.open(false)", "map.zoom(10000)"
        ])
        #expect(panel.mapSection.isOverridden)
        panel.mapSection.performResetToDefaults()
        #expect(provider.menuCalls.mapMode == nil)
    }

    @Test
    func readoutsNameTheStateInPlainLines() {
        let map = MapMenuSnapshot(
            mode: "world", markerCount: 3, visibleCount: 2, discoveredCount: 1,
            selected: "Riverwood", cameraHeight: 50000, cameraPitch: 50,
            questTargets: ["Get the claw"], fastTravelEnabled: false, lastResult: nil
        )
        #expect(MapMenuSection.readout(for: map) == """
        Map: world
        Markers: 1 found, 2 shown of 3
        Selected: Riverwood
        Fast travel: off by script
        Camera: 50000 high, 50 degrees
        Quest targets: Get the claw
        """)
        let title = TitleMenuSnapshot(
            isOpen: true, rows: ["New", "Load"], selectedIndex: 1, isLoadPageOpen: false,
            lastResult: nil
        )
        #expect(TitleMenuSection
            .readout(for: title) == "Title menu: open, Main page\n  New\n> Load\nMovie: off")
        let movie = TitleMenuMovieSnapshot(
            isEnabled: true, isLoaded: true, rows: ["$NEW", "$QUIT"], state: "Main"
        )
        #expect(TitleMenuSection.movieLine(movie) == "Movie: Main, rows $NEW $QUIT")
        let race = RaceMenuSnapshot(
            isOpen: false, isLimited: false, isEditingName: false, rows: [], selectedIndex: 0,
            lastResult: "Ada, Nord, Female"
        )
        #expect(RaceMenuSection
            .readout(for: race) == "Race menu: closed\nLast character: Ada, Nord, Female")
        let page = SystemMenuPageSnapshot(
            page: "quit", rows: ["Main Menu", "Desktop", "Cancel"], selectedIndex: 2,
            question: nil, message: "Quicksave"
        )
        #expect(SystemMenuPageSection.readout(for: page) == """
        Page: quit
          Main Menu
          Desktop
        > Cancel
        Last result: Quicksave
        """)
    }
}
