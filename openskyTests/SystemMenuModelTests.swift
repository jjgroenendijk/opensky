// The system menu selector (M8.5.1) is toolkit-free and movie-free, so its
// transitions are pinned here without AppKit, a renderer, or the install.

@testable import opensky
import Testing

struct SystemMenuModelTests {
    @Test
    func startsClosedWithThreeEntries() {
        let model = SystemMenuModel()
        #expect(!model.isOpen)
        #expect(model.entries == [.resume, .settings, .quit])
        #expect(model.entries.map(\.title) == ["Resume", "Settings", "Quit"])
        #expect(model.selectedEntry == .resume)
        #expect(model.lastOutcome == nil)
    }

    @Test
    func identifierFragmentsCapitalizeTheRawValue() {
        #expect(SystemMenuEntry.resume.identifierFragment == "Resume")
        #expect(SystemMenuEntry.settings.identifierFragment == "Settings")
        #expect(SystemMenuEntry.quit.identifierFragment == "Quit")
    }

    @Test
    func openStartsAtTheFirstRow() {
        var model = SystemMenuModel()
        model.moveSelection(.down)
        #expect(model.selectedIndex == 0, "a closed menu ignores input")
        model.open()
        #expect(model.isOpen)
        #expect(model.selectedIndex == 0)
        #expect(!model.settingsRevealed)
    }

    @Test
    func reopeningDoesNotResetSelection() {
        var model = SystemMenuModel()
        model.open()
        model.moveSelection(.down)
        model.open()
        #expect(model.selectedIndex == 1)
    }

    @Test
    func verticalMovesWrapAndHorizontalMovesAreIgnored() {
        var model = SystemMenuModel()
        model.open()
        model.moveSelection(.down)
        #expect(model.selectedEntry == .settings)
        model.moveSelection(.down)
        #expect(model.selectedEntry == .quit)
        model.moveSelection(.down)
        #expect(model.selectedEntry == .resume, "the list wraps forward")
        model.moveSelection(.up)
        #expect(model.selectedEntry == .quit, "the list wraps backward")
        model.moveSelection(.left)
        model.moveSelection(.right)
        #expect(model.selectedEntry == .quit, "a one-column list ignores horizontal moves")
    }

    @Test
    func activatingResumeClosesTheMenu() {
        var model = SystemMenuModel()
        model.open()
        #expect(model.activateSelection() == .resume)
        #expect(!model.isOpen)
        #expect(model.selectedIndex == 0)
        #expect(model.lastOutcome == .resume)
    }

    @Test
    func activatingSettingsRevealsThePlaceholdersAndKeepsTheMenuOpen() {
        var model = SystemMenuModel()
        model.open()
        model.moveSelection(.down)
        #expect(model.activateSelection() == .showSettings)
        #expect(model.isOpen)
        #expect(model.settingsRevealed)
        #expect(model.lastOutcome == .showSettings)
    }

    @Test
    func activatingQuitReportsQuitWithoutClosing() {
        var model = SystemMenuModel()
        model.open()
        model.moveSelection(.up)
        #expect(model.selectedEntry == .quit)
        #expect(model.activateSelection() == .quit)
        // Terminating is the host's job; the model must not pretend it happened.
        #expect(model.isOpen)
        #expect(model.lastOutcome == .quit)
    }

    @Test
    func closeClearsRevealedSettingsAndSelection() {
        var model = SystemMenuModel()
        model.open()
        model.moveSelection(.down)
        model.activateSelection()
        model.close()
        #expect(!model.isOpen)
        #expect(!model.settingsRevealed)
        #expect(model.selectedIndex == 0)
    }

    @Test
    func cancelResumes() {
        var model = SystemMenuModel()
        model.open()
        model.moveSelection(.down)
        #expect(model.handle(.button(.cancel)) == .resume)
        #expect(!model.isOpen)
        #expect(model.lastOutcome == .resume)
    }

    @Test
    func closedMenuSwallowsEveryEvent() {
        var model = SystemMenuModel()
        #expect(model.handle(.button(.accept)) == nil)
        #expect(model.handle(.move(.down)) == nil)
        #expect(model.handle(.button(.cancel)) == nil)
        #expect(!model.isOpen)
    }

    @Test
    func pointerMotionIsConsumedWithoutChangingSelection() {
        var model = SystemMenuModel()
        model.open()
        #expect(model.handle(.pointer(deltaX: 12, deltaY: -4)) == nil)
        #expect(model.selectedIndex == 0)
    }

    @Test
    func acceptRoutesThroughHandle() {
        var model = SystemMenuModel()
        model.open()
        model.handle(.move(.down))
        #expect(model.handle(.button(.accept)) == .showSettings)
        #expect(model.settingsRevealed)
    }

    @Test
    func outcomeLabelsMatchTheRowTitles() {
        #expect(SystemMenuOutcome.resume.label == "Resume")
        #expect(SystemMenuOutcome.showSettings.label == "Settings")
        #expect(SystemMenuOutcome.quit.label == "Quit")
    }

    @Test
    func anEmptyEntryListFallsBackToTheFullSet() {
        let model = SystemMenuModel(entries: [])
        #expect(model.entries == SystemMenuEntry.allCases)
    }
}
