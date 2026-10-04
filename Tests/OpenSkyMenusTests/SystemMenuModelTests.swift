// System menu selector transitions, without AppKit, a renderer, or the install.

@testable import OpenSkyMenus
import Testing

struct SystemMenuModelTests {
    @Test
    func startsClosedWithTheVanillaRows() {
        let model = SystemMenuModel()
        #expect(!model.isOpen)
        #expect(model.entries == [.resume, .quicksave, .save, .load, .settings, .controls, .quit])
        #expect(model.entries.map(\.title) == [
            "Resume", "Quicksave", "Save", "Load", "Settings", "Controls", "Quit"
        ])
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
        #expect(model.selectedEntry == .quicksave)
        model.moveSelection(.up)
        model.moveSelection(.up)
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
    func activatingSettingsOpensItsPageAndKeepsTheMenuOpen() {
        var model = SystemMenuModel()
        model.open()
        model.select(.settings)
        #expect(model.activateSelection() == .showPage(.settings))
        #expect(model.isOpen)
        #expect(model.settingsRevealed)
        #expect(model.page == .settings)
        #expect(model.lastOutcome == .showPage(.settings))
    }

    @Test
    func eachRowOpensItsPage() {
        let pages: [SystemMenuEntry: SystemMenuPage] = [
            .save: .save, .load: .load, .controls: .controls, .quit: .quit
        ]
        for (entry, page) in pages {
            var model = SystemMenuModel()
            model.open()
            model.select(entry)
            #expect(model.activateSelection() == .showPage(page))
            #expect(model.page == page)
        }
    }

    @Test
    func quicksaveStaysOnTheMainPage() {
        var model = SystemMenuModel()
        model.open()
        model.select(.quicksave)
        #expect(model.activateSelection() == .quicksave)
        #expect(model.isOpen)
        #expect(model.page == .main)
    }

    @Test
    func aSubPageIgnoresMainPageEventsUntilShowMain() {
        var model = SystemMenuModel()
        model.open()
        model.select(.quit)
        model.activateSelection()
        #expect(model.handle(.button(.cancel)) == nil, "the quit page handles its own cancel")
        #expect(model.isOpen)
        model.showMain()
        #expect(model.page == .main)
    }

    @Test
    func closeClearsRevealedSettingsAndSelection() {
        var model = SystemMenuModel()
        model.open()
        model.select(.settings)
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
        model.select(.settings)
        #expect(model.handle(.button(.accept)) == .showPage(.settings))
        #expect(model.settingsRevealed)
    }

    @Test
    func outcomeLabelsMatchTheRowTitles() {
        #expect(SystemMenuOutcome.resume.label == "Resume")
        #expect(SystemMenuOutcome.showPage(.settings).label == "Settings")
        #expect(SystemMenuOutcome.showPage(.quit).label == "Quit")
        #expect(SystemMenuOutcome.quicksave.label == "Quicksave")
    }

    @Test
    func anEmptyEntryListFallsBackToTheFullSet() {
        let model = SystemMenuModel(entries: [])
        #expect(model.entries == SystemMenuEntry.allCases)
    }
}
