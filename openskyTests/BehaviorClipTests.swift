// `hkbClipGenerator` evaluation (issue #187): local time advance, playback
// modes, triggers, and root-motion extraction.
//
// These run over the shared synthetic spline packfile, so time advance is
// asserted through the same `HKASplineCompressedAnimation` sampling the engine
// uses rather than through a stand-in. Nothing here is extracted from a game
// file (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import opensky
import simd
import Testing

struct BehaviorClipTests {
    private let tolerance: Float = 0.01

    // MARK: - Clip time

    @Test func clipTimeAdvancesWithTheTimestep() throws {
        // The synthetic clip runs one second and ramps translation.x 0 to 30,
        // so a quarter second in is x = 7.5 and half a second in is x = 15.
        let (graph, _) = try splineGraph(mode: 1)
        #expect(abs(graph.update(deltaTime: 0.25).bones[1].translation.x - 7.5) < tolerance)
        #expect(abs(graph.update(deltaTime: 0.25).bones[1].translation.x - 15) < tolerance)
    }

    @Test func playbackSpeedScalesTheAdvance() throws {
        let (graph, _) = try splineGraph(mode: 1, playbackSpeed: 2)
        #expect(abs(graph.update(deltaTime: 0.25).bones[1].translation.x - 15) < tolerance)
    }

    @Test func aLoopingClipWrapsPastItsEnd() throws {
        let (graph, _) = try splineGraph(mode: 1)
        graph.update(deltaTime: 0.8)
        // 0.8 + 0.3 = 1.1, which wraps to 0.1 and samples x = 3.
        #expect(abs(graph.update(deltaTime: 0.3).bones[1].translation.x - 3) < tolerance)
    }

    @Test func aSinglePlayClipStopsAtItsEnd() throws {
        let (graph, _) = try splineGraph(mode: 0)
        graph.update(deltaTime: 0.8)
        graph.update(deltaTime: 0.8)
        #expect(abs(graph.update(deltaTime: 0.8).bones[1].translation.x - 30) < tolerance)
    }

    @Test func startTimePlacesAFreshlyActivatedClip() throws {
        let (graph, _) = try splineGraph(mode: 1, startTime: 0.5)
        // Seeded at 0.5, then advanced by the first step.
        #expect(abs(graph.update(deltaTime: 0.1).bones[1].translation.x - 18) < tolerance)
    }

    @Test func pingPongPlaybackIsRunAsALoopAndTallied() throws {
        let (graph, _) = try splineGraph(mode: 3)
        graph.update(deltaTime: 0.5)
        #expect(graph.tally.featureGaps["clipPingPongAsLoop"] == 1)
    }

    @Test func anUnresolvedClipLeavesTheReferencePoseAndOneTallyEntry() {
        var table = BehaviorObjectTable()
        let root = table.add(
            BehaviorFixture.clipGenerator("missing", animationName: "nowhere"), at: 0x100
        )
        let graph = BehaviorFixture.instance(root: root, table: table)
        let result = graph.update(deltaTime: 1 / 30)
        #expect(result.bones == BehaviorFixture.skeleton().referencePose)
        #expect(graph.tally.unresolvedClips["nowhere"] == 1)
    }

    // MARK: - Triggers

    @Test func aTriggerFiresOnTheUpdateThatStepsOverIt() throws {
        let (graph, _) = try splineGraph(
            mode: 1,
            triggers: [BehaviorTriggerSpec(
                localTime: 0.5,
                eventId: 0,
                relativeToEnd: false,
                acyclic: false
            )],
            events: ["mark"]
        )
        // The trigger is raised during the first update, so it is visible to
        // the second: nothing a node raises is visible to its own update.
        #expect(graph.update(deltaTime: 0.6).firedEvents.isEmpty)
        #expect(graph.update(deltaTime: 0.1).firedEvents.map(\.name) == ["mark"])
        #expect(graph.update(deltaTime: 0.1).firedEvents.isEmpty)
    }

    /// `m_relativeToEndOfClip` carries an offset *from* the end, and vanilla
    /// writes it negative: `0_master.hkx`'s `MT_JumpLand` clip carries its
    /// `JumpLandEnd` trigger at -0.8, meaning 0.8 seconds before the clip ends.
    /// So the absolute time is the window length plus the offset. Subtracting
    /// it instead put the trigger past the end of the clip, where nothing ever
    /// crossed it, and parked the vanilla player graph in `JumpLandState`
    /// forever (issue #189).
    @Test func aTriggerRelativeToTheEndIsOffsetFromIt() throws {
        let (graph, _) = try splineGraph(
            mode: 1,
            triggers: [BehaviorTriggerSpec(
                localTime: -0.2,
                eventId: 0,
                relativeToEnd: true,
                acyclic: false
            )],
            events: ["mark"]
        )
        graph.update(deltaTime: 0.5)
        #expect(graph.update(deltaTime: 0.1).firedEvents.isEmpty)
        // 0.5 + 0.4 = 0.9, which steps over the 0.8 mark.
        graph.update(deltaTime: 0.3)
        #expect(graph.update(deltaTime: 0.05).firedEvents.map(\.name) == ["mark"])
    }

    /// A positive offset from the end names a time past the clip, which nothing
    /// can cross. Refused rather than folded back inside, because a trigger
    /// outside its own clip is malformed data and guessing at it would fire an
    /// event the author never placed.
    @Test func aTriggerPastTheEndOfTheClipNeverFires() throws {
        let (graph, _) = try splineGraph(
            mode: 1,
            triggers: [BehaviorTriggerSpec(
                localTime: 0.2,
                eventId: 0,
                relativeToEnd: true,
                acyclic: false
            )],
            events: ["mark"]
        )
        var fired = 0
        for _ in 0 ..< 60 {
            fired += graph.update(deltaTime: 0.1).firedEvents.count
        }
        #expect(fired == 0)
    }

    @Test func anAcyclicTriggerFiresOnTheFirstCycleOnly() throws {
        let (graph, _) = try splineGraph(
            mode: 1,
            triggers: [BehaviorTriggerSpec(
                localTime: 0.5,
                eventId: 0,
                relativeToEnd: false,
                acyclic: true
            )],
            events: ["mark"]
        )
        var fired = 0
        for _ in 0 ..< 60 {
            fired += graph.update(deltaTime: 0.1).firedEvents.count
        }
        #expect(fired == 1)
    }

    // MARK: - Root motion

    @Test func rootMotionIsExtractedAndKeptOutOfThePose() throws {
        let clip = try BehaviorFixture.splineClip(boneIndex: 0)
        var table = BehaviorObjectTable()
        let root = table.add(
            BehaviorFixture.clipGenerator("walk", animationName: "walk"), at: 0x100
        )
        let graph = BehaviorFixture.instance(
            root: root, table: table, clips: BehaviorClipTable(byName: ["walk": clip])
        )
        let result = graph.update(deltaTime: 0.5)
        // Half a second of the ramp is 15 units of travel on the root bone...
        #expect(abs(result.rootMotion.translation.x - 15) < tolerance)
        // ...and the pose's root bone stays at the skeleton's reference pose.
        #expect(result.bones[0] == BehaviorFixture.skeleton().referencePose[0])
    }

    @Test func rootMotionAcrossALoopSeamAddsBothRuns() throws {
        let clip = try BehaviorFixture.splineClip(boneIndex: 0)
        var table = BehaviorObjectTable()
        let root = table.add(
            BehaviorFixture.clipGenerator("walk", animationName: "walk"), at: 0x100
        )
        let graph = BehaviorFixture.instance(
            root: root, table: table, clips: BehaviorClipTable(byName: ["walk": clip])
        )
        graph.update(deltaTime: 0.8)
        // 0.8 to 1.0 is 6 units, then 0.0 to 0.1 is another 3: 9 in total, not
        // the -21 a naive difference of samples would report.
        let wrapped = graph.update(deltaTime: 0.3)
        #expect(abs(wrapped.rootMotion.translation.x - 9) < tolerance)
    }

    // MARK: - Helpers

    /// A clip generator over the shared synthetic spline clip, with optional
    /// triggers, ready to step.
    private func splineGraph(
        mode: Int,
        playbackSpeed: Float = 1,
        startTime: Float = 0,
        triggers: [BehaviorTriggerSpec] = [],
        events: [String] = []
    ) throws -> (BehaviorGraphInstance, HKXPointerTarget) {
        let clip = try BehaviorFixture.splineClip()
        var table = BehaviorObjectTable()
        let triggerTarget = triggers.isEmpty
            ? nil
            : table.add(BehaviorFixture.clipTriggers(triggers), at: 0x80)
        let root = table.add(
            BehaviorFixture.clipGenerator(
                "walk",
                animationName: "walk",
                mode: mode,
                playbackSpeed: playbackSpeed,
                startTime: startTime,
                triggers: triggerTarget
            ),
            at: 0x100
        )
        let graph = BehaviorFixture.instance(
            root: root,
            table: table,
            data: BehaviorFixture.graphData(events: events),
            clips: BehaviorClipTable(byName: ["walk": clip])
        )
        return (graph, root)
    }
}
