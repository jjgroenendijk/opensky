// Developer > UI Lab > SWF movie section coverage (M8.2.5): the popup mirrors
// the provider's movie list, selecting an entry drives selectSWFMovie(path:),
// the layer toggle round-trips, and the readout renders the movie tally, the
// draw stats, unresolved fonts, and load failures instead of crashing. The
// accessibility ids are pinned literally — they are the UI-test API while
// make test-ui is blocked on this machine (docs/tools/app-ui.md).

import AppKit
@testable import opensky
import Testing

struct SWFMovieSectionTests {
    @MainActor
    private static func makeSection(
        paths: [String] = ["interface\\console.swf", "interface\\hudmenu.swf"]
    ) -> (SWFMovieSection, FakeSWFLabProvider) {
        let section = SWFMovieSection()
        let provider = FakeSWFLabProvider()
        provider.swfMoviePaths = paths
        section.provider = provider
        section.loadViewIfNeeded()
        return (section, provider)
    }

    @Test @MainActor
    func controlsHaveVisibleFrames() {
        let (section, _) = Self.makeSection()
        section.view.frame = NSRect(x: 0, y: 0, width: 300, height: 300)
        section.view.layoutSubtreeIfNeeded()
        for control: NSView in [section.movieControl, section.layerEnabledControl] {
            #expect(!control.isHidden)
            #expect(control.frame.height > 0, "\(control) frame=\(control.frame)")
        }
    }

    @Test @MainActor
    func accessibilityIdentifiersAreStable() {
        let (section, _) = Self.makeSection()
        #expect(section.movieControl.accessibilityIdentifier() == "SWFMovieControl")
        #expect(section.layerEnabledControl.accessibilityIdentifier() == "SWFLayerEnabledControl")
        #expect(section.sectionIdentifier == "swfMovie")
        #expect(section.sectionTitle == "SWF movie")
    }

    @Test @MainActor
    func popupListsNoneFollowedByTheProviderMovies() {
        let (section, _) = Self.makeSection()
        #expect(section.movieControl.itemTitles == ["None", "console.swf", "hudmenu.swf"])
        #expect(section.movieControl.indexOfSelectedItem == 0)
        #expect(section.movieControl.isEnabled)
    }

    /// No located install: only the clearing entry remains and the picker
    /// disables rather than disappearing or crashing.
    @Test @MainActor
    func popupDegradesWithoutGameData() {
        let (section, _) = Self.makeSection(paths: [])
        #expect(section.movieControl.itemTitles == ["None"])
        #expect(!section.movieControl.isEnabled)
        #expect(section.statsReadout.contains("no game data"))
    }

    @Test @MainActor
    func selectingAMovieDrivesTheProvider() {
        let (section, provider) = Self.makeSection()
        section.movieControl.selectItem(at: 2)
        section.movieControl.sendAction(
            section.movieControl.action,
            to: section.movieControl.target
        )
        #expect(provider.selections == ["interface\\hudmenu.swf"])

        section.movieControl.selectItem(at: 0)
        section.movieControl.sendAction(
            section.movieControl.action,
            to: section.movieControl.target
        )
        #expect(provider.selections == ["interface\\hudmenu.swf", nil])
    }

    @Test @MainActor
    func layerToggleRoundTrips() {
        let (section, provider) = Self.makeSection()
        section.syncControls()
        #expect(section.layerEnabledControl.state == .on)

        section.layerEnabledControl.state = .off
        section.layerEnabledControl.sendAction(
            section.layerEnabledControl.action, to: section.layerEnabledControl.target
        )
        #expect(provider.swfLayerEnabled == false)
    }

    @Test @MainActor
    func syncSelectsTheAssignedMovie() {
        let (section, provider) = Self.makeSection()
        provider.snapshot = SWFLabControlSnapshot(
            selectedPath: "interface\\hudmenu.swf",
            layerEnabled: true,
            loadError: nil,
            tally: nil,
            unresolvedFontNames: [],
            drawStats: SWFDrawStats(),
            installLoaded: true,
            runtime: nil
        )
        section.syncControls()
        #expect(section.movieControl.titleOfSelectedItem == "hudmenu.swf")
    }

    @Test @MainActor
    func readoutRendersTallyAndDrawStats() {
        let (section, provider) = Self.makeSection()
        var tally = SWFMovieTally()
        tally.placeObject2 = 12
        tally.placeObject3 = 5
        tally.sprites = 7
        tally.clipLayers = 3
        tally.clipActions = 9
        tally.actionBlocks = 17
        tally.actionRecords = 940
        tally.unknownActionOpcodes = 0
        provider.snapshot = SWFLabControlSnapshot(
            selectedPath: "interface\\hudmenu.swf",
            layerEnabled: true,
            loadError: nil,
            tally: tally,
            unresolvedFontNames: ["$MissingFont"],
            drawStats: SWFDrawStats(
                drawCalls: 185, triangles: 4321, glyphs: 24, maskDraws: 24, skippedItems: 2
            ),
            installLoaded: true,
            runtime: nil
        )
        section.refreshReadout()

        let readout = section.statsReadout
        for token in [
            "hudmenu.swf", "layer on", "12", "5", "7", "3", "9",
            "17 blocks", "940 records", "unknown 0", "undecoded 0", "warnings 0",
            "185", "4321", "24", "skipped 2", "$MissingFont"
        ] {
            #expect(readout.contains(token), "missing \(token) in: \(readout)")
        }
    }

    @Test @MainActor
    func readoutSurfacesLoadFailures() {
        let (section, provider) = Self.makeSection()
        provider.snapshot = SWFLabControlSnapshot(
            selectedPath: "interface\\broken.swf",
            layerEnabled: false,
            loadError: "unsupportedCompression(\"ZWS\")",
            tally: nil,
            unresolvedFontNames: [],
            drawStats: SWFDrawStats(),
            installLoaded: true,
            runtime: nil
        )
        section.refreshReadout()
        let readout = section.statsReadout
        #expect(readout.contains("[ERROR] unsupportedCompression"))
        #expect(readout.contains("layer off"))
        #expect(readout.contains("Tags: no movie loaded"))
    }

    @Test @MainActor
    func readoutDegradesWithoutAProvider() {
        let section = SWFMovieSection()
        section.loadViewIfNeeded()
        section.refreshReadout()
        #expect(section.statsReadout == "SWF state unavailable.")
    }

    @Test
    func displayNameStripsTheArchiveFolder() {
        #expect(SWFLabReadout.displayName(for: "interface\\console.swf") == "console.swf")
        #expect(SWFLabReadout.displayName(for: "console.swf") == "console.swf")
    }
}
