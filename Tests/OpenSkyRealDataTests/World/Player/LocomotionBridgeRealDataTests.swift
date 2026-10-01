// Locomotion drive on the real install: the vanilla player graph
// (`0_master.hkx`) on the locomotion bridge, driven by scripted input through
// `WalkController` over the launch cell's LAND. Travel moves forward within the
// install's gait speed, a jump leaves the ground and lands, and every census
// name is declared. The per-step trace goes to `logs/`.

import Foundation
@testable import OpenSkyBehavior
@testable import OpenSkyFormatsAnimation
@testable import OpenSkyGameData
@testable import OpenSkyPhysics
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import simd
import Testing

struct LocomotionBridgeRealDataTests {
    private static let behaviorPath =
        "meshes\\actors\\character\\behaviors\\0_master.hkx"
    private static let skeletonPath =
        "meshes\\actors\\character\\character assets\\skeleton.hkx"
    private static let animationPrefix = "meshes\\actors\\character\\animations\\"
    private static let step = LocomotionDriveHarness.step
    private static let secondOfSteps = LocomotionDriveHarness.secondOfSteps

    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func drivesTheVanillaGraphThroughACell() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let harness = try harness(root: root)
        let configuration = harness.bridge.configuration

        let walked = harness.run(
            input: CameraInput(moveForward: 1, dt: Self.step),
            steps: Self.secondOfSteps,
            label: "walk"
        )
        #expect(walked.isMonotoneForward)
        // Bounded above by the gait's own distance — the graph may not add
        // travel — and far enough along to prove it actually moved.
        #expect(walked.distance <= configuration.walkSpeed.value + 1)
        #expect(walked.distance > configuration.walkSpeed.value / 2)

        let sprinted = harness.run(
            input: CameraInput(moveForward: 1, sprint: true, dt: Self.step),
            steps: Self.secondOfSteps,
            label: "sprint"
        )
        #expect(sprinted.isMonotoneForward)
        #expect(sprinted.distance > walked.distance)
        #expect(sprinted.distance <= configuration.sprintSpeed.value + 1)

        let sneaked = harness.run(
            input: CameraInput(moveForward: 1, sprint: true, sneak: true, dt: Self.step),
            steps: Self.secondOfSteps,
            label: "sneak"
        )
        #expect(sneaked.distance < walked.distance)

        assertJumpArc(harness)
        assertBindings(harness)
        try write(harness.log.joined(separator: "\n") + "\n")
    }

    // MARK: - Assertions

    private func assertJumpArc(_ harness: LocomotionDriveHarness) {
        #expect(harness.controller.isGrounded)
        let jump = harness.jump(steps: Self.secondOfSteps * 4)
        #expect(jump.leftGround)
        #expect(jump.landed)
        // The takeoff speed is derived from fJumpHeightMin (76 units in
        // Skyrim.esm), so the arc reaches roughly that height rather than an
        // arbitrary one.
        #expect(jump.apex - jump.floor > 60)
        #expect(jump.apex - jump.floor < 120)
        #expect(harness.bridge.status.raisedEvents.contains(LocomotionGraphNames.jumpUp))
        #expect(harness.bridge.status.raisedEvents.contains(LocomotionGraphNames.jumpLand))
    }

    /// Every census name the bridge writes and raises has to exist in the
    /// player's own graph. `0_master.hkx` is the entry point all three vanilla
    /// character files name, so a miss here is a name OpenSky invented rather
    /// than one it read out of the data.
    private func assertBindings(_ harness: LocomotionDriveHarness) {
        let status = harness.bridge.status
        harness.note("bound variables: \(status.boundVariables)")
        harness.note("missing variables: \(status.missingVariables)")
        harness.note("raised events: \(status.raisedEvents)")
        harness.note("missing events: \(status.missingEvents)")
        harness.note("graph updates: \(status.graphUpdates)")
        #expect(status.missingVariables.isEmpty)
        #expect(status.missingEvents.isEmpty)
        #expect(status.boundVariables.count == LocomotionGraphNames.variables.count)
        #expect(status.graphUpdates > 0)
    }

    // MARK: - Loading

    /// The bridge, the real graph, the install's own gait speeds, and the
    /// launch cell's terrain, assembled into one driveable harness.
    private func harness(root: GameDataRoot) throws -> LocomotionDriveHarness {
        let vfs = VirtualFileSystem(root: root)
        let graph = try instance(vfs)
        let configuration = PlayerMovementConfiguration.resolve(
            store: GameSettingLoader.load(root: root),
            movementTypes: MovementTypeLoader.load(root: root)
        )
        let terrain = try #require(LocomotionRealTerrain.terrainField(root: root))
        let harness = LocomotionDriveHarness(
            bridge: LocomotionBridge(configuration: configuration, graph: graph),
            terrain: terrain,
            start: LocomotionRealTerrain.startPosition(on: terrain)
        )
        harness.note("OpenSky locomotion drive — \(Self.behaviorPath)")
        harness.note(
            "gaits: walk \(configuration.walkSpeed.value) [\(configuration.walkSpeed.source)], "
                + "run \(configuration.runSpeed.value), "
                + "sprint \(configuration.sprintSpeed.value), "
                + "sneak \(configuration.sneakSpeed.value), "
                + "swim \(configuration.swimSpeed.value), "
                + "jump \(configuration.jumpTakeoffSpeed.value)"
        )
        harness.note(
            "cell \(FirstRenderCell.gridX),\(FirstRenderCell.gridY) "
                + "start \(harness.controller.feetPosition)"
        )
        graph.activate()
        return harness
    }

    private func instance(_ vfs: VirtualFileSystem) throws -> BehaviorGraphInstance {
        let file = try HKXFile(data: vfs.contents(forPath: Self.behaviorPath))
        let objectGraph = try HKXObjectGraph(file: file)
        let behavior = try #require(HKBBehaviorGraph.graphs(in: objectGraph).first)
        let skeletonData = try vfs.contents(forPath: Self.skeletonPath)
        let rig = try #require(try HKASkeleton.skeletons(in: HKXFile(data: skeletonData)).first)
        let paths = vfs.archiveEntries()
            .map(\.path)
            .filter { $0.hasPrefix(Self.animationPrefix) && $0.hasSuffix(".hkx") }
        return BehaviorGraphInstance(
            graph: behavior,
            in: objectGraph,
            skeleton: BehaviorSkeleton(rig),
            clips: InstallBehaviorClipSource(fileSystem: vfs, paths: paths)
        )
    }

    private func write(_ report: String) throws {
        let directory = try RepositoryLogs.directory()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        try report.write(
            to: directory.appending(path: "locomotion-drive.log"),
            atomically: true,
            encoding: .utf8
        )
    }
}
