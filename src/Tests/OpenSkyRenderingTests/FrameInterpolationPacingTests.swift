// When real frames are too slow to pace interpolation, and how the present gaps turn into
// the pacing readout.

import Foundation
@testable import OpenSkyRendering
import Testing

struct FrameInterpolationPacingTests {
    private static let display = 1.0 / 60

    private static func pauses(work: Double, paused: Bool = false) -> Bool {
        FrameInterpolationPacing.shouldPause(
            realFrameWork: work, displayInterval: display, paused: paused
        )
    }

    @Test
    func realFramesThatFitTwoDisplayIntervalsKeepInterpolating() {
        #expect(!Self.pauses(work: 1.9 * Self.display))
        #expect(!Self.pauses(work: Self.display / 2))
    }

    @Test
    func slowRealFramesPauseInterpolation() {
        // 45 ms at 60 Hz: the built image would show 17 ms and the real one about 30 ms.
        #expect(Self.pauses(work: 0.045))
    }

    @Test
    func aPausedInterpolatorResumesOnlyWellInsideTheBudget() {
        #expect(Self.pauses(work: 1.9 * Self.display, paused: true))
        #expect(!Self.pauses(work: 1.5 * Self.display, paused: true))
    }

    @Test
    func thePauseReasonNamesBothTimes() {
        let reason = FrameInterpolationPacing.pauseReason(
            realFrameWork: 0.045, displayInterval: Self.display
        )
        #expect(reason == "Paused: real frames take 45 ms, interpolation needs under 33 ms")
    }

    @Test
    func theSmoothedIntervalMovesATenthTowardTheNewOne() {
        #expect(FrameInterpolationPacing.smoothed(nil, adding: 0.05) == 0.05)
        let smoothed = FrameInterpolationPacing.smoothed(0.05, adding: 0.15)
        #expect(abs(smoothed - 0.06) < 1e-9)
    }

    @Test
    func aGapOverOneAndAHalfMediansCountsAsAHitch() throws {
        let pacing = try #require(PresentPacing(gapsMS: [16.7, 16.7, 16.6, 50, 16.7]))
        #expect(pacing.hitches == 1)
        #expect(pacing.longestGapMS == 50)
        #expect(abs(pacing.averageGapMS - 23.34) < 0.01)
        #expect(PresentPacing(gapsMS: []) == nil)
    }

    @Test
    func theInboxReportsGapsBetweenShownImagesAndKeepsThemWhenNothingShows() {
        let inbox = PresentLatencyInbox()
        inbox.recordShown(1.0)
        inbox.recordShown(1.02)
        inbox.recordShown(0)
        inbox.recordShown(1.04)
        let first = inbox.take()
        #expect(first.pacing?.hitches == 0)
        #expect(abs((first.pacing?.averageGapMS ?? 0) - 20) < 1e-6)
        #expect(inbox.take() == first)
    }
}
