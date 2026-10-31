// The wait and rest menu: refusals, the text panel's hours, the movie's calls, and the
// rest rule's order.

import Foundation
import OpenSkyFormatsESM
import OpenSkyFormatsSWF
@testable import OpenSkyMenus
import OpenSkyRenderCore
import OpenSkyRendering
import Testing

@MainActor
final class FakeSleepWaitWorld: SleepWaitWorld, MenuInputConsumer {
    var renderer: Renderer? {
        nil
    }

    var viewCamera: FreeFlyCamera? {
        nil
    }

    var uiScene = UIScene.empty
    var gameDateText: String? = "Sundas, 1:00 PM, 17th of Last Seed, 4E 201"
    var refusal: String?
    var passed: [(hours: Int, sleeping: Bool)] = []
    var hudLines: [String] = []

    var askedBeds: [FormID?] = []

    func restRefusal(sleeping: Bool, bed: FormID?) -> String? {
        askedBeds.append(bed)
        return refusal
    }

    func passTime(hours: Int, sleeping: Bool) {
        passed.append((hours, sleeping))
    }

    func showHUDNotification(_ text: String) {
        hudLines.append(text)
    }

    var menuInputConsumer: (any MenuInputConsumer)? {
        self
    }

    func handleMenuInput(_ event: MenuInputEvent) {}
}

@MainActor
struct SleepWaitMenuCoordinatorTests {
    @Test func aRefusalShowsItsTextAndKeepsTheMenuShut() {
        let world = FakeSleepWaitWorld()
        world.refusal = "You cannot wait in the air."
        let menu = SleepWaitMenuCoordinator(menuMode: MenuModeController(), world: world)
        #expect(!menu.open(sleeping: false))
        #expect(world.hudLines == ["You cannot wait in the air."])
        #expect(menu.lastResult == "Refused: You cannot wait in the air.")
    }

    @Test func theTextPanelChoosesHoursWithinTheSliderRange() {
        let world = FakeSleepWaitWorld()
        let menuMode = MenuModeController()
        let menu = SleepWaitMenuCoordinator(menuMode: menuMode, world: world)
        #expect(menu.open(sleeping: true))
        #expect(menuMode.topMenu == SleepWaitMenuCoordinator.identifier)
        menu.route(.move(.left))
        #expect(menu.chosenHours == 1)
        for _ in 0 ..< 30 {
            menu.route(.move(.right))
        }
        #expect(menu.chosenHours == 24)
        menu.route(.button(.accept))
        #expect(world.passed.map(\.hours) == [24])
        #expect(world.passed.map(\.sleeping) == [true])
        #expect(!menu.isOpen)
        #expect(menuMode.topMenu == nil)
        #expect(menu.lastResult == "Rested 24 h")
    }

    @Test func theMovieCallsWaitAndCancel() throws {
        let runtime = try MenuMovieCallLog.emptyRuntime()
        let events = MenuMovieEventLog<SleepWaitMovieEvent>()
        SleepWaitMenuMovieBridge.prepare(runtime: runtime) { events.append($0) }
        runtime.callHost("OK", arguments: [.number(5)])
        runtime.callHost("Cancel", arguments: [])
        #expect(events.events == [.wait(hours: 5), .cancel])
    }

    @Test func aBedOpensTheRestMenuAndNamesItselfToTheRefusalCheck() {
        let world = FakeSleepWaitWorld()
        let menu = SleepWaitMenuCoordinator(menuMode: MenuModeController(), world: world)
        #expect(menu.open(sleeping: true, bed: FormID(0x0001_2345)))
        #expect(menu.isSleeping)
        #expect(world.askedBeds == [FormID(0x0001_2345)])
    }

    @Test func anOutOfRangeHourIsClamped() {
        let world = FakeSleepWaitWorld()
        let menu = SleepWaitMenuCoordinator(menuMode: MenuModeController(), world: world)
        menu.open(sleeping: false)
        menu.handle(.wait(hours: 99))
        #expect(world.passed.map(\.hours) == [24])
    }

    @Test func enemiesComeBeforeTheOtherReasons() {
        var context = RestContext()
        context.inAir = true
        context.hostilesNear = true
        #expect(RestRule.refusal(context) == .hostileActorsNear)
        #expect(RestRefusal.inAir.settingEditorID(sleeping: false) == "sNoWaitInAir")
        #expect(RestRefusal.alarm.settingEditorID(sleeping: true) == "sNoSleepWhileAlarm")
        #expect(RestRule.refusal(RestContext()) == nil)
    }

    @Test func chargenWaitingLockComesFirst() {
        var context = RestContext()
        context.hostilesNear = true
        context.waitingDisabled = true
        #expect(RestRule.refusal(context) == .disabled)
        #expect(RestRefusal.disabled.settingEditorID(sleeping: false) == "sNoWaitDefault")
        #expect(RestRefusal.disabled.settingEditorID(sleeping: true) == "sNoSleepDefault")
    }

    /// The Can't Wait flag refuses both menus with their own texts.
    @Test func aCantWaitCellRefusesBeforeEnemies() {
        var context = RestContext()
        context.hostilesNear = true
        context.cellForbidsWaiting = true
        #expect(RestRule.refusal(context) == .cell)
        #expect(RestRefusal.cell.settingEditorID(sleeping: false) == "sNoWaitInCell")
        #expect(RestRefusal.cell.settingEditorID(sleeping: true) == "sNoSleepInCell")
    }
}

struct RestStepTests {
    @Test func timePassesInQuarterHourSteps() {
        #expect(RestTimeSteps.steps(hours: 1) == [0.25, 0.5, 0.75, 1])
        #expect(RestTimeSteps.steps(hours: 24).count == 96)
        #expect(RestTimeSteps.steps(hours: 0).isEmpty)
    }

    @Test func anOwnedBedAndTrespassRefuseAfterTheAlarm() {
        var context = RestContext()
        context.bedOwnedByOther = true
        #expect(RestRule.refusal(context) == .ownedBed)
        #expect(RestRefusal.ownedBed.settingEditorID(sleeping: true) == "sNoSleepInOwnedBed")
        context.trespassing = true
        #expect(RestRule.refusal(context) == .trespass)
        #expect(RestRefusal.trespass.settingEditorID(sleeping: false) == "sNoWaitTrespass")
        context.warnedToLeave = true
        #expect(RestRule.refusal(context) == .warnedToLeave)
        #expect(RestRefusal.warnedToLeave.settingEditorID(sleeping: true) == "sNoSleepWarnToLeave")
        context.alarmed = true
        #expect(RestRule.refusal(context) == .alarm)
    }
}
