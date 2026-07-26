// World > System Menu acceptance-surface coverage. Synthetic provider state
// only; the real-install movie bring-up gate is the env-gated acceptance test.

import AppKit
@testable import opensky
import Testing

struct SystemMenuPanelTests {
    @MainActor
    private func makePanel(
        _ provider: FakeWorldProviders
    ) -> SystemMenuPanelViewController {
        let panel = SystemMenuPanelViewController()
        panel.provider = provider
        panel.loadViewIfNeeded()
        return panel
    }

    @Test @MainActor
    func sectionsExposeStableIdentifiers() {
        let panel = makePanel(FakeWorldProviders())
        #expect(panel.menuSection.sectionIdentifier == "systemMenu")
        #expect(panel.settingsSection.sectionIdentifier == "systemMenuSettings")
        let controls: [(NSControl, String)] = [
            (panel.menuSection.openControl, "SystemMenuOpenControl"),
            (panel.menuSection.resumeControl, "SystemMenuResumeControl"),
            (panel.menuSection.upControl, "SystemMenuUpControl"),
            (panel.menuSection.downControl, "SystemMenuDownControl"),
            (panel.menuSection.activateControl, "SystemMenuActivateControl"),
            (panel.menuSection.movieControl, "SystemMenuMovieControl"),
            (panel.settingsSection.volumeControl, "SystemMenuMasterVolumeControl")
        ]
        for (control, identifier) in controls {
            #expect(control.accessibilityIdentifier() == identifier)
        }
    }

    @Test @MainActor
    func buttonsDriveTheProviderAndNavigationButtonsUnlockOnOpen() {
        let provider = FakeWorldProviders()
        let panel = makePanel(provider)
        let section = panel.menuSection

        section.refreshReadout()
        #expect(section.openControl.isEnabled)
        #expect(!section.activateControl.isEnabled, "navigation is locked while closed")

        send(section.openControl)
        #expect(provider.systemMenuIsOpen)
        section.refreshReadout()
        #expect(!section.openControl.isEnabled)
        #expect(section.activateControl.isEnabled)

        send(section.downControl)
        #expect(provider.systemMenuSnapshot.selectedIndex == 1)
        send(section.activateControl)
        #expect(provider.systemMenuSnapshot.settingsRevealed)
        #expect(provider.systemMenuIsOpen, "Settings keeps the menu open")

        send(section.resumeControl)
        #expect(!provider.systemMenuIsOpen)
        #expect(provider.refocusCount == 4)
    }

    @Test @MainActor
    func upButtonWrapsToQuit() {
        let provider = FakeWorldProviders()
        let panel = makePanel(provider)
        send(panel.menuSection.openControl)
        send(panel.menuSection.upControl)
        #expect(provider.systemMenuSnapshot.selectedIndex == 2)
    }

    @Test @MainActor
    func anOpenMenuOrAnEnabledMovieCountsAsAnOverride() {
        let provider = FakeWorldProviders()
        #expect(!SystemMenuSection.isOverridden(provider: provider))

        provider.openSystemMenu()
        #expect(SystemMenuSection.isOverridden(provider: provider))
        SystemMenuSection.resetToDefaults(provider: provider)
        #expect(!provider.systemMenuIsOpen)

        provider.systemMenuMovieEnabled = true
        #expect(SystemMenuSection.isOverridden(provider: provider))
        SystemMenuSection.resetToDefaults(provider: provider)
        #expect(!provider.systemMenuMovieEnabled)
    }

    @Test @MainActor
    func volumeSliderWritesThroughAndResets() {
        let provider = FakeWorldProviders()
        let panel = makePanel(provider)
        let section = panel.settingsSection
        #expect(!SystemMenuSettingsSection.isOverridden(provider: provider))

        section.volumeControl.floatValue = 0.25
        send(section.volumeControl)
        #expect(provider.systemMenuMasterVolume == 0.25)
        #expect(SystemMenuSettingsSection.isOverridden(provider: provider))

        section.performResetToDefaults()
        #expect(provider.systemMenuMasterVolume == 1)
    }

    @Test
    func closedReadoutNamesTheWorldSimState() {
        let snapshot = Self.snapshot(isOpen: false)
        #expect(SystemMenuSection
            .readout(for: snapshot) == "System menu: closed · world sim running")
    }

    @Test
    func openReadoutMarksTheSelectionAndTheStack() {
        let snapshot = Self.snapshot(
            isOpen: true, selectedIndex: 1, lastOutcome: "Settings",
            openMenus: ["SystemMenu"], worldSimPaused: true
        )
        let readout = SystemMenuSection.readout(for: snapshot)
        #expect(readout.contains("world sim paused"))
        #expect(readout.contains("Stack: SystemMenu"))
        #expect(readout.contains("  Resume"))
        #expect(readout.contains("> Settings"))
        #expect(readout.contains("Last action: Settings"))
        #expect(readout.contains("Movie: off (engine-drawn selector)"))
    }

    @Test
    func movieReadoutReportsLoadStateFaultsAndErrors() {
        var snapshot = Self.snapshot(isOpen: true, movieEnabled: true)
        #expect(SystemMenuSection.movieReadout(for: snapshot) == "Movie: not loaded")

        snapshot = Self.snapshot(isOpen: true, movieEnabled: true, movieError: "boom")
        #expect(SystemMenuSection.movieReadout(for: snapshot) == "Movie: failed · boom")

        snapshot = Self.snapshot(
            isOpen: true, movieEnabled: true, movieLoaded: true,
            drawCalls: 144, faults: 0, missingNames: 32,
            movieEntryTitles: ["$NEW", "$LOAD", "$QUIT"], movieState: "Main"
        )
        let readout = SystemMenuSection.movieReadout(for: snapshot)
        #expect(readout.contains(SystemMenuMovieBridge.moviePath))
        #expect(readout.contains("144 draws"))
        #expect(readout.contains("0 faults"))
        #expect(readout.contains("32 missing names"))
        #expect(readout.contains("state Main"))
        #expect(readout.contains("Movie rows: $NEW, $LOAD, $QUIT"))

        snapshot = Self.snapshot(isOpen: true, movieEnabled: true, movieLoaded: true)
        #expect(SystemMenuSection.movieReadout(for: snapshot).contains("Movie rows: no rows"))
    }

    @Test
    func dataRootReadoutNamesThePathAndTheSource() {
        var snapshot = Self.snapshot(isOpen: false)
        #expect(SystemMenuSettingsSection
            .dataRootReadout(for: snapshot) == "Data root: not located")

        snapshot = Self.snapshot(
            isOpen: false, dataRootPath: "/games/Skyrim", dataRootSource: "Steam default"
        )
        let readout = SystemMenuSettingsSection.dataRootReadout(for: snapshot)
        #expect(readout.contains("/games/Skyrim"))
        #expect(readout.contains("(source: Steam default)"))
    }

    @Test
    func settingsReadoutTracksTheRevealedState() {
        let hidden = Self.snapshot(isOpen: true)
        #expect(SystemMenuSettingsSection.readout(for: hidden).contains("not revealed"))
        let shown = Self.snapshot(isOpen: true, settingsRevealed: true, audioEnabled: true)
        let readout = SystemMenuSettingsSection.readout(for: shown)
        #expect(readout.contains("Settings row: revealed"))
        #expect(readout.contains("audio engine on"))
    }

    private static func snapshot(
        isOpen: Bool,
        selectedIndex: Int = 0,
        lastOutcome: String? = nil,
        settingsRevealed: Bool = false,
        openMenus: [String] = [],
        worldSimPaused: Bool = false,
        dataRootPath: String? = nil,
        dataRootSource: String? = nil,
        audioEnabled: Bool = false,
        movieEnabled: Bool = false,
        movieLoaded: Bool = false,
        movieError: String? = nil,
        drawCalls: Int = 0,
        faults: Int = 0,
        missingNames: Int = 0,
        movieEntryTitles: [String] = [],
        movieState: String? = nil
    ) -> SystemMenuControlSnapshot {
        SystemMenuControlSnapshot(
            isOpen: isOpen,
            entryTitles: SystemMenuEntry.allCases.map(\.title),
            selectedIndex: selectedIndex,
            lastOutcome: lastOutcome,
            settingsRevealed: settingsRevealed,
            openMenus: openMenus,
            worldSimPaused: worldSimPaused,
            dataRootPath: dataRootPath,
            dataRootSource: dataRootSource,
            masterVolume: 1,
            audioEnabled: audioEnabled,
            movieEnabled: movieEnabled,
            movieLoaded: movieLoaded,
            movieError: movieError,
            movieDrawStats: SWFDrawStats(drawCalls: drawCalls),
            movieFaults: faults,
            movieMissingNames: missingNames,
            movieEntryTitles: movieEntryTitles,
            movieState: movieState
        )
    }

    @MainActor
    private func send(_ control: NSControl) {
        control.sendAction(control.action, to: control.target)
    }
}
