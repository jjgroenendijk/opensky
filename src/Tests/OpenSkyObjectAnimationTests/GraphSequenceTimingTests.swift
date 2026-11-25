// A mesh sequence's text keys reach its graph in seconds from the sequence's start.

import OpenSkyBehavior
import OpenSkyFormatsMesh
@testable import OpenSkyObjectAnimation
import Testing

struct GraphSequenceTimingTests {
    @Test func aSequencesKeysAreTimedFromItsStartAtItsFrequency() throws {
        let intro = NIFSequence(
            name: "mIntro",
            timing: ControllerTiming(
                cycle: .clamp,
                frequency: 2,
                phase: 0,
                startTime: 1,
                stopTime: 3
            ),
            textKeys: [NIFKey(time: 1, value: "start"), NIFKey(time: 3, value: "end")],
            tracks: []
        )
        let idle = NIFSequence(
            name: "mIdle",
            timing: ControllerTiming(
                cycle: .loop,
                frequency: 1,
                phase: 0,
                startTime: 0,
                stopTime: 1
            ),
            textKeys: [], tracks: []
        )

        let timings = GamebryoSequenceTiming.byName([intro, idle])

        let timing = try #require(timings["mIntro"])
        #expect(timing.duration == 1)
        #expect(!timing.loops)
        #expect(timing.keys.map(\.time) == [0, 1])
        #expect(timing.keys.map(\.name) == ["start", "end"])
        #expect(timings["mIdle"]?.loops == true)
    }
}
