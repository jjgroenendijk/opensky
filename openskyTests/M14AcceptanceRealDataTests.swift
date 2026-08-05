// M14 acceptance against the user's own read-only Skyrim SE install (issue
// #191): the same route the synthetic gate drives, over the vanilla player
// behavior graph, with the coverage tally pinned rather than described.
//
// This is the honest-coverage half of the gate. `M14AcceptanceTests` proves the
// route works over a graph OpenSky wrote; what this proves is that the graph
// the install ships survives the same route — every class it reaches decoded,
// every census name bound, every clip resolved or counted, and the evaluator's
// own tally reported with numbers instead of adjectives.
//
// The whole thing is device-free on purpose (the M13 env-gated/device-gated
// split): the motion, state, streaming and tally evidence stands on a runner
// with no GPU, and only the pixel evidence in `M14AcceptanceRenderTests` needs
// one.
//
// Nothing from the install is committed: the report goes to gitignored `logs/`
// and carries class names and counts only — never clip data, never a pose. Run
// it with `make realtest T='M14AcceptanceRealDataTests/...'`, which supplies
// the data root and the RSS watchdog.

import Foundation
@testable import opensky
import simd
import Testing

struct M14AcceptanceRealDataTests {
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    private static let step = LocomotionDriveHarness.step
    private static let secondOfSteps = LocomotionDriveHarness.secondOfSteps

    @Test(.enabled(if: Self.dataRoot != nil))
    func drivesTheWholeRouteThroughTheVanillaPlayerGraph() throws {
        let root = try #require(Self.dataRoot)
        let vfs = VirtualFileSystem(root: root)
        let graph = try PlayerBehaviorGraph.load(fileSystem: vfs)
        let firstPerson = try PlayerBehaviorGraph.load(
            fileSystem: vfs,
            behaviorPath: PlayerBehaviorGraph.firstPersonBehaviorPath,
            skeletonPath: PlayerBehaviorGraph.firstPersonSkeletonPath
        )
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let configuration = PlayerMovementConfiguration.resolve(
            store: GameSettingLoader.load(root: root, baseFile: file),
            movementTypes: MovementTypeLoader.load(root: root, baseFile: file)
        )
        let bridge = LocomotionBridge(configuration: configuration, graph: graph.instance)
        bridge.attachFirstPerson(graph: firstPerson.instance)
        graph.instance.activate()
        firstPerson.instance.activate()

        let terrain = try #require(LocomotionRealTerrain.terrainField(root: root))
        let harness = LocomotionDriveHarness(
            bridge: bridge,
            terrain: terrain,
            start: LocomotionRealTerrain.startPosition(on: terrain)
        )
        harness.note("OpenSky M14 acceptance route — \(PlayerBehaviorGraph.behaviorPath)")

        try Self.driveTheRoute(harness)
        Self.expectEveryCensusNameBound(harness)
        Self.expectTheGraphSurvivedTheRoute(graph.instance, label: "third person")
        Self.expectTheGraphSurvivedTheRoute(firstPerson.instance, label: "first person")
        Self.expectBothPerspectivesSawTheSameStep(bridge)
        try Self.write(harness: harness, graph: graph.instance, firstPerson: firstPerson.instance)
    }

    // MARK: - The route

    /// Every gait the milestone names, driven through the real controller over
    /// the launch cell's real terrain, then a jump, then a forced swim.
    ///
    /// Swimming is forced rather than waded into: the launch cell is dry land,
    /// and the point of the leg is that the vanilla graph answers a swim gait
    /// with swim states and swim clips. That is the `forcedGait` dev control
    /// doing exactly the job it was added for, and it is called out here so
    /// nothing reads the leg as a claim about that cell's water.
    private static func driveTheRoute(_ harness: LocomotionDriveHarness) throws {
        let configuration = harness.bridge.configuration
        let walked = harness.run(
            input: CameraInput(moveForward: 1, dt: step), steps: secondOfSteps, label: "walk"
        )
        // Distance rather than monotonicity, deliberately. A vanilla clip's
        // root bone jitters, and a step whose jitter crosses
        // `LocomotionBridge.rootMotionSpeedFloor` is driven by the clip for
        // that one step and can move the capsule backwards by a fraction of a
        // unit. Over this whole route that path contributes about two units
        // against several hundred — see the root-motion assertion below, and
        // issue #370 for the floor itself.
        #expect(walked.distance <= configuration.walkSpeed.value + 1)
        #expect(walked.distance > configuration.walkSpeed.value / 2)

        let ran = harness.run(
            input: CameraInput(moveForward: 1, boost: true, dt: step),
            steps: secondOfSteps,
            label: "run"
        )
        #expect(ran.distance > walked.distance)
        #expect(ran.distance <= configuration.runSpeed.value + 1)

        let sprinted = harness.run(
            input: CameraInput(moveForward: 1, sprint: true, dt: step),
            steps: secondOfSteps,
            label: "sprint"
        )
        #expect(sprinted.distance > ran.distance)
        #expect(sprinted.distance <= configuration.sprintSpeed.value + 1)

        let sneaked = harness.run(
            input: CameraInput(moveForward: 1, sneak: true, dt: step),
            steps: secondOfSteps,
            label: "sneak"
        )
        #expect(sneaked.distance < walked.distance)

        let jump = harness.jump(steps: secondOfSteps * 4)
        #expect(jump.leftGround)
        #expect(jump.landed)
        #expect(jump.apex - jump.floor > 60)

        harness.bridge.forcedGait = .swim
        let swum = harness.run(
            input: CameraInput(moveForward: 1, dt: step), steps: secondOfSteps, label: "swim"
        )
        harness.bridge.forcedGait = nil
        #expect(swum.distance <= configuration.swimSpeed.value + 1)
        #expect(harness.bridge.status.raisedEvents.contains(LocomotionGraphNames.swimStart))
        _ = harness.run(
            input: CameraInput(moveForward: 1, dt: step), steps: 4, label: "leaving the water"
        )
        #expect(harness.bridge.status.raisedEvents.contains(LocomotionGraphNames.swimStop))
    }

    // MARK: - Assertions

    /// Every census name the bridge writes and raises exists in the player's
    /// own graph, on both perspectives. A miss here is a name OpenSky invented
    /// rather than one it read out of the data.
    private static func expectEveryCensusNameBound(_ harness: LocomotionDriveHarness) {
        let status = harness.bridge.status
        #expect(status.missingVariables.isEmpty)
        #expect(status.missingEvents.isEmpty)
        #expect(status.boundVariables.count == LocomotionGraphNames.variables.count)
        #expect(status.firstPersonMissingVariables.isEmpty)
        #expect(status.firstPersonMissingEvents.isEmpty)
        #expect(status.graphUpdates > 0)
        #expect(status.firstPersonGraphUpdates == status.graphUpdates)
        // Vanilla locomotion clips animate in place, so the route is the
        // configured gait driving the capsule: the install's clips carry no
        // extracted motion, which is the #188 measurement. What root motion
        // does contribute is clip jitter on the handful of steps that cross
        // the speed floor — under half a percent of the travel, reported here
        // as a bound rather than assumed away, and filed as issue #370.
        #expect(status.configuredSpeedDistance > 0)
        #expect(status.rootMotionDistance < status.configuredSpeedDistance * 0.005)
    }

    /// The full-graph rule, as the route exercises it: nothing the graph
    /// reached was undecodable, and no reference went unresolved. Both are
    /// zero-tolerance — they are the "zero unresolved graph references" half of
    /// the gate — while the shortcut buckets are reported rather than
    /// forbidden, because an owed feature is a worklist entry and not a
    /// failure.
    private static func expectTheGraphSurvivedTheRoute(
        _ instance: BehaviorGraphInstance,
        label: String
    ) {
        let tally = instance.tally
        #expect(tally.undecodableObjectTotal == 0, "\(label): an object had no decoder")
        #expect(
            tally.featureGaps[BehaviorTally.Gap.unresolvedBehaviorReference.rawValue] == nil,
            "\(label): a behavior reference resolved to nothing"
        )
        #expect(
            tally.featureGaps[BehaviorTally.Gap.depthCapReached.rawValue] == nil,
            "\(label): the graph walk hit its depth cap"
        )
        #expect(tally.generatorsEvaluated > 0, "\(label): the route evaluated no generator")
        #expect(tally.updatesRun > 0)
    }

    /// Both graphs are fed from one place per variable and one per event, so
    /// they cannot have seen different state — asserted rather than trusted.
    private static func expectBothPerspectivesSawTheSameStep(_ bridge: LocomotionBridge) {
        let status = bridge.status
        #expect(status.boundVariables == status.firstPersonBoundVariables)
        #expect(status.raisedEvents == status.firstPersonRaisedEvents)
        // Except the one input that is meant to differ.
        #expect(
            bridge.graph?.variable(named: LocomotionGraphNames.isFirstPerson) == .bool(false)
        )
        #expect(
            bridge.firstPersonGraph?.variable(named: LocomotionGraphNames.isFirstPerson)
                == .bool(true)
        )
    }

    // MARK: - Evidence

    /// The coverage ledger the milestone's log entry quotes, written to
    /// gitignored `logs/`. Class names and counts only.
    private static func write(
        harness: LocomotionDriveHarness,
        graph: BehaviorGraphInstance,
        firstPerson: BehaviorGraphInstance
    ) throws {
        var lines = harness.log
        lines.append(contentsOf: report(graph.tally, label: "third person"))
        lines.append(contentsOf: report(firstPerson.tally, label: "first person"))
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "logs")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        try (lines.joined(separator: "\n") + "\n").write(
            to: directory.appending(path: "m14-acceptance-route.log"),
            atomically: true,
            encoding: .utf8
        )
    }

    private static func report(_ tally: BehaviorTally, label: String) -> [String] {
        [
            "[INFO] \(label): \(tally.generatorsEvaluated) generators, "
                + "\(tally.modifiersEvaluated) modifiers over \(tally.updatesRun) updates",
            "[INFO] \(label): gaps \(tally.gapTotal)"
                + "  unevaluated \(tally.unevaluatedGeneratorTotal)"
                + "  partial \(tally.partialGeneratorTotal)"
                + "  pass-through \(tally.passthroughModifierTotal)"
                + "  unresolved clips \(tally.unresolvedClipTotal)"
                + "  unapplied bindings \(tally.unappliedBindingTotal)"
                + "  undecodable \(tally.undecodableObjectTotal)",
            "[INFO] \(label): unevaluated generators \(tally.rankedUnevaluatedGenerators)",
            "[INFO] \(label): partial generators \(tally.rankedPartialGenerators)",
            "[INFO] \(label): pass-through modifiers \(tally.rankedPassthroughModifiers)",
            "[INFO] \(label): feature gaps \(tally.rankedFeatureGaps)",
            "[INFO] \(label): bound member paths \(tally.rankedBoundMemberPaths.prefix(10))"
        ]
    }
}
