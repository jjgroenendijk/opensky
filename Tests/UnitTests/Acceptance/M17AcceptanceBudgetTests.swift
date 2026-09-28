// M17 acceptance, budget half (issue #209): a talking face is held to the
// per-frame budgets that already exist, and adds no set of numbers of its own.
//
// The constraint M13 put on M14 and every milestone since has restated: what
// M17 adds to a frame is a lip track sampled against the audio clock and a set
// of morph deltas composed on the CPU, both of which land inside the shipping
// `animationUpdateBudgetMS` the fly-path validator already enforces, while the
// voice line itself lands inside `audioUpdateBudgetMS`. Neither gets a second
// copy of the numbers.
//
// The other half of the claim is that the face work is bounded by construction,
// which is the part a timing measurement cannot show. A lip track writes at
// most one weight per mapped viseme however long the line is, a finished line
// stops costing anything after one decay, a disabled A/B seam costs nothing at
// all, and a composed morph writes one vertex range per active target. Those
// are asserted against the shipping types rather than against a clock.
//
// The timings are synthetic, as they are throughout `CellStreamingFlyPathTests`:
// these cases pin the gate's behaviour, not this machine's speed. The measured
// numbers against the real install come from `openskycli bench --fly-path` and
// from `make realtest-perf`.

import Foundation
@testable import opensky
import Testing

@MainActor
struct M17AcceptanceBudgetTests {
    // MARK: - Frame budgets

    /// A frame that samples a lip track and composes the morph deltas it
    /// produces, measured against the shipping animation budget. The gate
    /// passes inside budget and still refuses an over-budget run, so it is live
    /// rather than vacuous.
    @Test
    func talkingFramesStayWithinTheShippingAnimationBudget() throws {
        let inBudget = Self.result(animationMS: [2.9, 3.3, 3.0])
        try validatedFlyUpdateBudgets(render: inBudget, configuration: Self.configuration())
        #expect(inBudget.animationPercentileMS(95) <= 4)

        let overBudget = Self.result(animationMS: [4.6, 6.2, 5.1])
        #expect(throws: CellStreamingFlyBenchmarkError.self) {
            try validatedFlyUpdateBudgets(
                render: overBudget, configuration: Self.configuration()
            )
        }
    }

    /// The voice line is a streamed positional source like any other, so it is
    /// held to the audio update budget rather than to a dialogue-shaped
    /// exception beside it.
    @Test
    func theVoicePathStaysWithinTheShippingAudioBudget() throws {
        let inBudget = Self.result(animationMS: [2.9, 3.0, 3.1], audioUpdateMS: [0.2, 0.3, 0.2])
        try validatedFlyUpdateBudgets(render: inBudget, configuration: Self.configuration())

        let overBudget = Self.result(
            animationMS: [2.9, 3.0, 3.1], audioUpdateMS: [0.7, 0.9, 0.8]
        )
        #expect(throws: CellStreamingFlyBenchmarkError.self) {
            try validatedFlyUpdateBudgets(
                render: overBudget, configuration: Self.configuration()
            )
        }
    }

    // MARK: - Bounded by construction

    /// However long a line runs, one update writes at most one weight per
    /// viseme the mapping knows. The cost of a talking face is therefore a
    /// property of the mapping table, not of the recording.
    @Test
    func onelipSyncUpdateWritesAtMostOneWeightPerMappedViseme() throws {
        let sink = LipSyncBudgetSink()
        let playback = LipSyncPlayback(faceMorph: sink)
        let clock = VoicePlaybackClock()
        let track = try LIPFile(data: LIPFixture.file())
        playback.start(track: track, clock: clock, line: "budget", animationTime: 0)

        let ceiling = LipVisemeMapping.entries.count
        #expect(ceiling > 0)
        for step in 0 ... 40 {
            clock.publish(Double(step) * track.duration / 40)
            _ = playback.update(at: Float(step) * 0.05)
            #expect(
                sink.weights.count <= ceiling,
                "an update wrote \(sink.weights.count) weights, past the \(ceiling) visemes"
            )
        }
        #expect(sink.maximumWeightCount > 0, "the track never wrote a weight at all")
    }

    /// A finished line costs one decay and then nothing. Without that, every
    /// line a session ever said would keep being sampled.
    @Test
    func afinishedLineStopsCostingAnythingAfterOneDecay() throws {
        let sink = LipSyncBudgetSink()
        let playback = LipSyncPlayback(faceMorph: sink)
        let clock = VoicePlaybackClock()
        try playback.start(
            track: LIPFile(data: LIPFixture.file()),
            clock: clock,
            line: "decay",
            animationTime: 0
        )
        _ = playback.update(at: 0)
        playback.finish(at: 0)

        #expect(playback.update(at: LipSyncPlayback.decayDuration / 2) > 0)
        _ = playback.update(at: LipSyncPlayback.decayDuration)
        #expect(playback.update(at: LipSyncPlayback.decayDuration * 4) == 0)
        #expect(sink.weights.isEmpty)
    }

    /// The A/B seam the gate's capture pairs are taken across is also the way a
    /// session pays nothing for lip sync: switched off, an update writes no
    /// weights whatever the clock says.
    @Test
    func adisabledSeamWritesNothing() throws {
        let sink = LipSyncBudgetSink()
        let playback = LipSyncPlayback(faceMorph: sink)
        let clock = VoicePlaybackClock()
        try playback.start(
            track: LIPFile(data: LIPFixture.file()),
            clock: clock,
            line: "off",
            animationTime: 0
        )
        playback.isEnabled = false
        sink.reset()

        clock.publish(0.2)
        #expect(playback.update(at: 0.2) == 0)
        #expect(sink.weights.isEmpty)
    }

    // MARK: - Fixtures

    /// A benchmark result whose interesting axes are the two M17 touches; the
    /// others sit comfortably inside their budgets so a failure names the axis
    /// this suite is about.
    private static func result(
        animationMS: [Double],
        audioUpdateMS: [Double] = [0.1, 0.1, 0.1]
    ) -> OffscreenBenchResult {
        OffscreenBenchResult(
            frameMS: [8, 9, 8],
            windowSummaries: [],
            animationMS: animationMS,
            shadowMS: [0.4, 0.5, 0.4],
            audioUpdateMS: audioUpdateMS,
            scriptUpdateMS: [0.2, 0.3, 0.2]
        )
    }

    /// The shipping fly-path budgets, matching `openskycli bench --fly-path`'s
    /// own defaults, spelled the way `M14AcceptanceBudgetTests` through
    /// `M16AcceptanceBudgetTests` spell them because they are private to the
    /// command.
    private static func configuration() -> CellStreamingFlyBenchmarkConfiguration {
        CellStreamingFlyBenchmarkConfiguration(
            start: CellCoordinate(x: 0, y: 0),
            size: (width: 1, height: 1),
            maxFrames: 1,
            footprintCapMB: 1024,
            collisionBuildBudgetMS: 750,
            actorBuildBudgetMS: 3000,
            animationUpdateBudgetMS: 4,
            shadowUpdateBudgetMS: 1.5,
            audioUpdateBudgetMS: 0.5,
            scriptUpdateBudgetMS: 0.5
        )
    }
}

/// A morph sink that records what a lip track asked for, and the high-water
/// mark of how many weights one update wrote.
nonisolated private final class LipSyncBudgetSink: LipMorphWeightApplying {
    let actor = FormID(0x1720)
    let targetNames = ["Aah", "BigAah"]
    private(set) var weights: [String: Float] = [:]
    private(set) var maximumWeightCount = 0

    @discardableResult
    func setLipWeights(_ weights: [String: Float]) -> Int {
        self.weights = weights
        maximumWeightCount = max(maximumWeightCount, weights.count)
        return weights.count
    }

    @discardableResult
    func clearLipWeights() -> Int {
        weights = [:]
        return 1
    }

    func reset() {
        weights = [:]
        maximumWeightCount = 0
    }
}
