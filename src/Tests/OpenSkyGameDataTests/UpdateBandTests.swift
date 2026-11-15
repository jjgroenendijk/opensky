// The shared distance bands and the clock that spreads far work over frames.

import OpenSkyFormatsESM
import OpenSkyGameData
import Testing

struct UpdateBandTests {
    @Test func theStandardBandsFollowTheActorGraphDistances() {
        let bands = UpdateBands.standard
        #expect(bands.band(atDistance: 0) == .full)
        #expect(bands.band(atDistance: 1024) == .full)
        #expect(bands.band(atDistance: 1500) == .near)
        #expect(bands.band(atDistance: 4000) == .reduced)
        #expect(bands.band(atDistance: 6145) == .distant)
        #expect(bands.band(atDistance: .nan) == .full)
        #expect(UpdateBand.full < .near && UpdateBand.reduced < .distant)
        #expect(UpdateBand.allCases.map(\.name) == ["full", "near", "reduced", "distant"])
    }

    @Test func aFullBandClockStepsEveryFrame() {
        var clock = UpdateBandClock(phase: 0.7)
        for _ in 0 ..< 3 {
            #expect(clock.tick(1.0 / 60, band: .full) == 1.0 / 60)
        }
    }

    /// 60 frames of 1/60 s in the reduced band: about 15 steps that together cover the
    /// second, less what waits for the next step.
    @Test func aFarClockStepsLessOftenAndLosesNoTime() {
        var clock = UpdateBandClock(phase: 0)
        var steps: [Float] = []
        for _ in 0 ..< 60 {
            if let step = clock.tick(1.0 / 60, band: .reduced) {
                steps.append(step)
            }
        }
        #expect((12 ... 15).contains(steps.count))
        let covered = steps.reduce(0, +)
        #expect(covered <= 1 + 1e-4 && covered > 1 - UpdateBand.reduced.interval)
        #expect(clock.band == .reduced)
    }

    @Test func theLongestIntervalCapsADistantClock() {
        var clock = UpdateBandClock(phase: 0)
        var count = 0
        for _ in 0 ..< 60 where clock.tick(1.0 / 60, band: .distant, longest: 1.0 / 15) != nil {
            count += 1
        }
        #expect((12 ... 15).contains(count))
    }

    /// Two clocks with different phases take their first step in different frames. Frames
    /// of 1/64 s add up exactly: the distant band's 0.2 s is due in frame 13, or in frame
    /// 7 with half of the interval taken off.
    @Test func aPhaseMovesTheFirstStepEarlier() {
        func firstStep(phase: Float) -> Int? {
            var clock = UpdateBandClock(phase: phase)
            return (0 ..< 60).first { _ in clock.tick(1.0 / 64, band: .distant) != nil }
        }
        #expect(firstStep(phase: 0) == 12)
        #expect(firstStep(phase: 0.5) == 6)
    }

    /// Time waited in a far band goes into the first step once the object comes near.
    @Test func comingNearStepsWithTheTimeWaited() {
        var clock = UpdateBandClock(phase: 0)
        #expect(clock.tick(0.05, band: .distant) == nil)
        let step = clock.tick(0.01, band: .full)
        #expect(step.map { abs($0 - 0.06) < 1e-6 } == true)
    }

    @Test func phasesOfNeighbouringKeysSpreadOverTheInterval() {
        let phases = (0 ..< 8).map {
            UpdateBandClock.phase(of: ReferenceKey.plugin(
                name: "skyrim.esm",
                objectID: UInt32(0x100 + $0)
            ))
        }
        #expect(phases.allSatisfy { (0 ..< 1).contains($0) })
        #expect(Set(phases.map { Int($0 * 4) }).count >= 3)
        #expect(UpdateBandClock.phase(of: .player) == UpdateBandClock.phase(of: 0))
    }
}
