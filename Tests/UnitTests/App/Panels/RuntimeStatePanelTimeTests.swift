// World > Runtime State > Time verification surface (issue #166, roadmap item
// 10.2.1): the clock scrub, the calendar scrub, the timescale write, and the
// pause readout.
//
// `make test-ui` is TCC-blocked on this machine (docs/tools/environment.md), so
// these unit tests are the evidence for the accessibility-id contract: every id
// this section declares is asserted literally, and every readout is read back
// through `runtimeStateReadout` by id rather than through the section's Swift
// property, which is what proves the UI-test API exists.

import AppKit
@testable import opensky
import Testing

struct RuntimeStatePanelTimeTests {
    @Test @MainActor
    func accessibilityIdentifiersArePinned() {
        let panel = RuntimeStatePanelViewController()
        panel.loadViewIfNeeded()
        #expect(panel.timeSection.sectionIdentifier == "runtimeStateTime")
        #expect(panel.runtimeStateHourControl
            .accessibilityIdentifier() == "RuntimeStateHourControl")
        #expect(panel.runtimeStateDayControl.accessibilityIdentifier() == "RuntimeStateDayControl")
        #expect(
            panel.runtimeStateMonthControl.accessibilityIdentifier() == "RuntimeStateMonthControl"
        )
        #expect(panel.runtimeStateYearControl
            .accessibilityIdentifier() == "RuntimeStateYearControl")
        #expect(
            panel.runtimeStateApplyDateControl.accessibilityIdentifier()
                == "RuntimeStateApplyDateControl"
        )
        #expect(
            panel.runtimeStateTimescaleControl.accessibilityIdentifier()
                == "RuntimeStateTimescaleControl"
        )
        #expect(
            panel.runtimeStateApplyTimescaleControl.accessibilityIdentifier()
                == "RuntimeStateApplyTimescaleControl"
        )
        #expect(runtimeStateReadout("RuntimeStateTimeStatsLabel", in: panel.view) != nil)
    }

    @Test @MainActor
    func readoutRendersTheClockCalendarTimescaleAndPauseState() throws {
        let panel = RuntimeStatePanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeRuntimeStateProvider()
        fake.runtimeStateClock = RuntimeStateClockSnapshot(
            clock: GameClock(year: 201, month: 8, day: 17, hour: 13.5),
            timescale: 60,
            isPaused: true
        )
        panel.provider = fake
        panel.startInspecting()
        defer { panel.stopInspecting() }

        let readout = try #require(
            runtimeStateReadout("RuntimeStateTimeStatsLabel", in: panel.view)
        )
        #expect(readout.contains("13:30"))
        #expect(readout.contains("17 Last Seed, 4E 201"))
        #expect(readout.contains("Timescale: 60"))
        #expect(readout.contains("World simulation: paused"))
    }

    /// A running simulation reads as running, so the readout distinguishes a
    /// paused clock from a stopped one.
    @Test @MainActor
    func pauseReadoutStatesARunningSimulation() throws {
        let panel = RuntimeStatePanelViewController()
        panel.loadViewIfNeeded()
        // Held in a local: `provider` is weak, so a temporary would be gone
        // before the first readout.
        let fake = FakeRuntimeStateProvider()
        panel.provider = fake
        panel.startInspecting()
        defer { panel.stopInspecting() }
        let readout = try #require(
            runtimeStateReadout("RuntimeStateTimeStatsLabel", in: panel.view)
        )
        #expect(readout.contains("World simulation: running"))
    }

    @Test @MainActor
    func hourSliderScrubsTheClockThroughTheProvider() {
        let panel = RuntimeStatePanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeRuntimeStateProvider()
        panel.provider = fake

        panel.runtimeStateHourControl.doubleValue = 6.25
        sendRuntimeStateControl(panel.runtimeStateHourControl)
        #expect(fake.hourCalls == [6.25])
        #expect(fake.runtimeStateClock.timeText == "06:15")
    }

    /// The date is applied as one unit, and the day is written after the month
    /// so a day beyond the new month's length clamps into that month.
    @Test @MainActor
    func applyDateWritesTheWholeCalendarDate() throws {
        let panel = RuntimeStatePanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeRuntimeStateProvider()
        panel.provider = fake

        panel.runtimeStateDayControl.stringValue = "3"
        panel.runtimeStateMonthControl.selectItem(at: 0)
        panel.runtimeStateYearControl.stringValue = "205"
        sendRuntimeStateControl(panel.runtimeStateApplyDateControl)

        let call = try #require(fake.dateCalls.first)
        #expect(call.day == 3)
        #expect(call.month == 1)
        #expect(call.year == 205)
        #expect(fake.runtimeStateClock.dateText == "3 Morning Star, 4E 205")
        // The controls resync from the provider, so the panel shows the clock's
        // answer rather than what was typed at it.
        #expect(panel.runtimeStateYearControl.stringValue == "205")
        #expect(panel.runtimeStateMonthControl.indexOfSelectedItem == 0)
    }

    /// A field that is not a number leaves that component alone rather than
    /// writing a guess.
    @Test @MainActor
    func applyDateKeepsTheCurrentComponentWhenAFieldIsNotANumber() throws {
        let panel = RuntimeStatePanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeRuntimeStateProvider()
        panel.provider = fake

        panel.runtimeStateDayControl.stringValue = "not a day"
        panel.runtimeStateYearControl.stringValue = ""
        panel.runtimeStateMonthControl.selectItem(at: 4)
        sendRuntimeStateControl(panel.runtimeStateApplyDateControl)

        let call = try #require(fake.dateCalls.first)
        #expect(call.day == RuntimeStateClockSnapshot.empty.day)
        #expect(call.year == RuntimeStateClockSnapshot.empty.year)
        #expect(call.month == 5)
    }

    @Test @MainActor
    func timescaleWriteReachesTheProviderAndReportsSuccess() throws {
        let panel = RuntimeStatePanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeRuntimeStateProvider()
        panel.provider = fake

        panel.runtimeStateTimescaleControl.stringValue = "120"
        sendRuntimeStateControl(panel.runtimeStateApplyTimescaleControl)
        #expect(fake.timescaleCalls == [120])
        let readout = try #require(
            runtimeStateReadout("RuntimeStateTimeStatsLabel", in: panel.view)
        )
        #expect(readout.contains("Timescale set to 120."))
        #expect(readout.contains("Timescale: 120"))
    }

    /// A session with no loaded plugins has no `TimeScale` global to write, and
    /// the readout has to say so rather than look like it worked.
    @Test @MainActor
    func timescaleWriteStatesAMissingGlobal() throws {
        let panel = RuntimeStatePanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeRuntimeStateProvider()
        fake.timescaleWriteSucceeds = false
        panel.provider = fake

        panel.runtimeStateTimescaleControl.stringValue = "120"
        sendRuntimeStateControl(panel.runtimeStateApplyTimescaleControl)
        let readout = try #require(
            runtimeStateReadout("RuntimeStateTimeStatsLabel", in: panel.view)
        )
        #expect(readout.contains("No TimeScale global is loaded"))
    }

    @Test @MainActor
    func nonNumericTimescaleIsRefusedRatherThanGuessedAt() throws {
        let panel = RuntimeStatePanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeRuntimeStateProvider()
        panel.provider = fake

        panel.runtimeStateTimescaleControl.stringValue = "fast"
        sendRuntimeStateControl(panel.runtimeStateApplyTimescaleControl)
        #expect(fake.timescaleCalls.isEmpty)
        let readout = try #require(
            runtimeStateReadout("RuntimeStateTimeStatsLabel", in: panel.view)
        )
        #expect(readout.contains("Timescale must be a number."))
    }

    /// Time passing is not an override; a timescale off the vanilla default is.
    @Test @MainActor
    func timescaleAloneDecidesTheSectionOverrideState() {
        let panel = RuntimeStatePanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeRuntimeStateProvider()
        panel.provider = fake
        #expect(!panel.timeSection.isOverridden)

        fake.setGameClockHour(3)
        fake.setGameClockDate(day: 1, month: 1, year: 300)
        #expect(!panel.timeSection.isOverridden)

        fake.setGameTimescale(500)
        #expect(panel.timeSection.isOverridden)

        panel.timeSection.performResetToDefaults()
        #expect(!panel.timeSection.isOverridden)
        #expect(fake.runtimeStateClock.timescale == GameClock.defaultTimescale)
    }
}
