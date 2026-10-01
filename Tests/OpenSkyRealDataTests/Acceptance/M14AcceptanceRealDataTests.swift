// Locomotion acceptance on the real install: the synthetic route over the
// vanilla player behavior graph. Every class the route reaches decodes, every
// census name binds, and the evaluator's tally is pinned. It needs no GPU;
// `M14AcceptanceRenderTests` holds the pixel half. The report in `logs/` holds
// class names and counts only.

import Foundation
@testable import OpenSkyBehavior
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyPhysics
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import simd
import Testing

struct M14AcceptanceRealDataTests {
    private static let step = LocomotionDriveHarness.step
    private static let secondOfSteps = LocomotionDriveHarness.secondOfSteps

    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func drivesTheWholeRouteThroughTheVanillaPlayerGraph() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
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

    /// Every gait over the launch cell's real terrain, then a jump and a swim.
    /// The cell is dry land, so the swim is forced with `forcedGait`; the leg
    /// checks the graph's swim states, not the cell's water.
    private static func driveTheRoute(_ harness: LocomotionDriveHarness) throws {
        let configuration = harness.bridge.configuration
        let walked = harness.run(
            input: CameraInput(moveForward: 1, dt: step), steps: secondOfSteps, label: "walk"
        )
        // Every walk step moves the capsule forward. A vanilla clip's root
        // bone jitters, and that jitter must not push a step backwards.
        #expect(walked.isMonotoneForward)
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
        // Vanilla locomotion clips animate in place (`m_extractedMotion` is
        // null), so only the gait moves the capsule, and clip motion is zero.
        #expect(status.configuredSpeedDistance > 0)
        #expect(status.rootMotionDistance == 0)
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
        let directory = try RepositoryLogs.directory()
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
