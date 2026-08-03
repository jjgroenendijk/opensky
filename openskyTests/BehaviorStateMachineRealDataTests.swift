// Env-gated state-machine drive over the user's own Skyrim SE install
// (read-only external input, never committed — AGENTS.md Legal & IP).
//
// Loads the vanilla third-person movement behavior, steps it headlessly, and
// raises the locomotion events the file itself declares. The assertions are on
// state *names* the file declares, so they say something about the graph rather
// than about ids that could drift.
//
// The report is names and counts only and goes to gitignored `logs/`. Skips
// automatically when OPENSKY_DATA_ROOT is unset. Run with
// `make realtest T='BehaviorStateMachineRealDataTests/walksThePlayerLocomotionStatePath()'`.

import Foundation
@testable import opensky
import Testing

struct BehaviorStateMachineRealDataTests {
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    private static let behaviorPath =
        "meshes\\actors\\character\\behaviors\\mt_behavior.hkx"
    private static let skeletonPath =
        "meshes\\actors\\character\\character assets\\skeleton.hkx"
    private static let animationPrefix = "meshes\\actors\\character\\animations\\"
    private static let timestep: Float = 1.0 / 30.0

    /// The machine and the two states this test drives, by the names the file
    /// declares. `MT_Default_Behavior` is the machine that separates standing
    /// from moving; `moveStart` and `moveStop` are the events its transitions
    /// name.
    private static let machineName = "MT_Default_Behavior"
    private static let standingState = "MT_Standing_State"
    private static let movingState = "MT_LocomotionType_State"

    @Test(.enabled(if: Self.dataRoot != nil))
    func walksThePlayerLocomotionStatePath() throws {
        let root = try #require(Self.dataRoot)
        let vfs = VirtualFileSystem(root: root)
        let instance = try instance(vfs)
        var log = ["OpenSky behavior state-path probe — \(Self.behaviorPath)"]

        instance.activate()
        settle(instance, updates: 4)
        log.append("start: " + path(instance))
        #expect(state(of: instance) == Self.standingState)

        #expect(instance.raiseEvent(named: "moveStart"))
        settle(instance, updates: 4)
        log.append("after moveStart: " + path(instance))
        #expect(state(of: instance) == Self.movingState)
        // The machine that runs only while moving is nested two levels under
        // the one the event moved, so reaching it proves the nesting walked.
        #expect(state(of: instance, machine: "MT_Locomotion_Behavior") != nil)

        #expect(instance.raiseEvent(named: "moveStop"))
        settle(instance, updates: 4)
        log.append("after moveStop: " + path(instance))
        #expect(state(of: instance) == Self.standingState)
        #expect(state(of: instance, machine: "MT_Locomotion_Behavior") == nil)

        // A second machine on the standing branch, driven by its own pair of
        // declared events, so the path is not one lucky transition.
        #expect(instance.raiseEvent(named: "SneakStart"))
        settle(instance, updates: 4)
        log.append("after SneakStart: " + path(instance))
        #expect(state(of: instance, machine: "MTIdleTurnTypeBehavior") == "SneakIdleTurnState")

        #expect(instance.raiseEvent(named: "SneakStop"))
        settle(instance, updates: 4)
        log.append("after SneakStop: " + path(instance))
        #expect(state(of: instance, machine: "MTIdleTurnTypeBehavior") == "MTIdleTurnState")

        try assertGaps(instance, log: &log)
        try write(log.joined(separator: "\n") + "\n")
    }

    // MARK: - Assertions

    /// Pins the tally: nothing undecodable, every generator reached, and no gap
    /// outside the recorded worklist. A new gap name here is a change that has
    /// to be documented before it lands.
    private func assertGaps(_ instance: BehaviorGraphInstance, log: inout [String]) throws {
        let known: Set = [
            "blenderParametricAsWeights",
            "blenderBoneWeights",
            "blenderSubtractLastChild",
            "clipPingPongAsLoop",
            "clipMirrored",
            "clipUserControlled",
            "depthCapReached",
            "disabledNode",
            "poseMatchingAsBlender",
            "stateMachineNoStartState",
            "stateMachineRandomTransitionFixed",
            "stateMachineTransitionInterrupted",
            "synchronizedClipMarkerIgnored",
            "transitionBlendCurveApproximated",
            "transitionConditionUnparsed",
            "transitionConditionUnresolved",
            "transitionEffectUnevaluated",
            "transitionFromNestedStateIgnored",
            "transitionStartFractionIgnored",
            "transitionStateChangeNotDelayed",
            "transitionTimeIntervalIgnored",
            "unresolvedBehaviorReference"
        ]
        let seen = Set(instance.tally.featureGaps.keys)
        #expect(seen.subtracting(known).isEmpty, "undocumented gaps: \(seen.subtracting(known))")
        #expect(instance.tally.undecodableObjectTotal == 0)
        #expect(instance.tally.generatorsEvaluated > 0)
        // The start-state-only shortcut item 14.3 tallied is gone: this item
        // evaluates transitions, so nothing may report it any more.
        #expect(instance.tally.featureGaps["stateMachineStartStateOnly"] == nil)
        log.append("")
        log.append("## Gaps (rank, count)")
        log += instance.tally.rankedFeatureGaps.map { "\($0.name) \($0.count)" }
        log.append("")
        log.append("generators evaluated: \(instance.tally.generatorsEvaluated)")
        log.append("modifiers evaluated: \(instance.tally.modifiersEvaluated)")
        log.append("machines reached: \(instance.activeStates.count)")
    }

    // MARK: - Driving

    private func settle(_ instance: BehaviorGraphInstance, updates: Int) {
        for _ in 0 ..< updates {
            instance.update(deltaTime: Self.timestep)
        }
    }

    /// The state one named machine is in right now, or nil when the walk did
    /// not reach it.
    private func state(
        of instance: BehaviorGraphInstance,
        machine: String = BehaviorStateMachineRealDataTests.machineName
    ) -> String? {
        instance.activeStates.first { $0.machineName == machine }?.stateName
    }

    /// Every machine's current state, for the report.
    private func path(_ instance: BehaviorGraphInstance) -> String {
        instance.activeStates
            .prefix(12)
            .map { "\($0.machineName ?? "?"):\($0.stateName ?? "?")" }
            .joined(separator: " > ")
    }

    // MARK: - Loading

    private func instance(_ vfs: VirtualFileSystem) throws -> BehaviorGraphInstance {
        let file = try HKXFile(data: vfs.contents(forPath: Self.behaviorPath))
        let objectGraph = try HKXObjectGraph(file: file)
        let behavior = try #require(HKBBehaviorGraph.graphs(in: objectGraph).first)
        let skeleton = try #require(loadSkeleton(vfs))
        let paths = vfs.archiveEntries()
            .map(\.path)
            .filter { $0.hasPrefix(Self.animationPrefix) && $0.hasSuffix(".hkx") }
        return BehaviorGraphInstance(
            graph: behavior,
            in: objectGraph,
            skeleton: skeleton,
            clips: InstallBehaviorClipSource(fileSystem: vfs, paths: paths)
        )
    }

    private func loadSkeleton(_ vfs: VirtualFileSystem) -> BehaviorSkeleton? {
        guard
            let data = try? vfs.contents(forPath: Self.skeletonPath),
            let file = try? HKXFile(data: data),
            let rig = (try? HKASkeleton.skeletons(in: file))?.first
        else {
            return nil
        }
        return BehaviorSkeleton(rig)
    }

    private func write(_ report: String) throws {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "logs")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        try report.write(
            to: directory.appending(path: "behavior-state-path.log"),
            atomically: true,
            encoding: .utf8
        )
    }
}
