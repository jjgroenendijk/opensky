// Env-gated player-locomotion drive over the user's own Skyrim SE install
// (read-only external input, never committed — AGENTS.md "Legal & IP").
//
// This is item 14.6's acceptance run. The vanilla player graph (`0_master.hkx`)
// and the vanilla player body (`NPC_ 00000007`) are loaded from the install, the
// body is bound to the graph through the same `PlayerPoseBuffer` the app uses,
// and a scripted input route drives the real `WalkController` over the launch
// cell's real LAND terrain: idle, walk, run, sprint, sneak, jump, land, and
// swim. What is asserted is that every state was actually reached, that the
// graph produced a distinct pose in each of them, and that the body's bone
// palettes moved with it.
//
// The per-step trace goes to gitignored `logs/`. Skips automatically when
// OPENSKY_DATA_ROOT is unset or the machine has no Metal 4 device (assembling
// the body uploads meshes). Run with
// `make realtest T='PlayerBodyRealDataTests/drivesEveryLocomotionStateWithABody()'`.

import Foundation
import Metal
@testable import opensky
import simd
import Testing

struct PlayerBodyRealDataTests {
    private static let device: MTLDevice? = {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            device.supportsFamily(.metal4)
        else { return nil }
        return device
    }()

    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    private static var canRun: Bool {
        device != nil && dataRoot != nil
    }

    private static let step = LocomotionDriveHarness.step
    private static let secondOfSteps = LocomotionDriveHarness.secondOfSteps

    @Test(.enabled(if: Self.canRun))
    @MainActor
    func drivesEveryLocomotionStateWithABody() throws {
        let device = try #require(Self.device)
        let root = try #require(Self.dataRoot)
        let assembled = try PlayerBodyFixture.assemble(device: device, root: root)
        let body = assembled.body

        // The body is a real actor: a skeleton, skinned body parts, and a
        // FaceGen head all resolved through the same path an ACHR takes.
        #expect(body.assembly.isRenderable)
        #expect(body.assembly.visual.skeletonPath != nil)
        #expect(!body.render.opaque.isEmpty || !body.render.alphaTested.isEmpty)

        let terrain = try #require(LocomotionRealTerrain.terrainField(root: root))
        let start = LocomotionRealTerrain.startPosition(on: terrain)
        let harness = LocomotionDriveHarness(
            bridge: assembled.bridge, terrain: terrain, start: start
        )
        harness.note("OpenSky player-body drive — \(PlayerBehaviorGraph.behaviorPath)")
        harness.note("player base \(PlayerBody.baseFormID.description), "
            + "skeleton \(body.assembly.visual.skeletonPath ?? "-"), "
            + "\(body.assembly.models.count) models")

        var seen: [LocomotionGait: [float4x4]] = [:]
        for leg in Self.route {
            let result = harness.run(
                input: leg.input, steps: Self.secondOfSteps, label: leg.label
            )
            body.place(
                feetPosition: harness.controller.feetPosition,
                yaw: harness.camera.yaw
            )
            let bones = body.animation.update(at: 0)
            harness.note(
                "\(leg.label): gait \(harness.bridge.status.gait.rawValue), "
                    + "distance \(result.distance), "
                    + "feet \(harness.controller.feetPosition), "
                    + "bones \(bones), "
                    + "graph states \(Self.activeStateNames(assembled.graph)), "
                    + "events \(assembled.bridge.status.recentGraphEvents)"
            )
            #expect(bones > 0, "\(leg.label) posed no bones")
            #expect(harness.bridge.status.gait == leg.gait)
            seen[leg.gait] = PlayerBodyFixture.palettes(of: body)
        }

        harness.note(Self.tallyLines(assembled.graph).joined(separator: "\n"))
        try assertJumpAndLanding(harness, body: body)
        seen[.swim] = try assertSwimming(harness, body: body)
        assertEveryGaitPosedDifferently(seen, note: harness.note)
        try PlayerBodyFixture.write(
            harness.log.joined(separator: "\n") + "\n",
            to: "player-locomotion-drive.log"
        )
    }

    // MARK: - Route

    private struct Leg {
        let label: String
        let gait: LocomotionGait
        let input: CameraInput
    }

    /// One second of each held input, in the order a user would try them. Swim
    /// is driven by the water surface the fixture injects rather than by an
    /// input, which is why it holds the same forward key as walking.
    private static let route: [Leg] = [
        Leg(label: "idle", gait: .walk, input: CameraInput(dt: step)),
        Leg(label: "walk", gait: .walk, input: CameraInput(moveForward: 1, dt: step)),
        Leg(
            label: "run",
            gait: .run,
            input: CameraInput(moveForward: 1, boost: true, dt: step)
        ),
        Leg(
            label: "sprint",
            gait: .sprint,
            input: CameraInput(moveForward: 1, sprint: true, dt: step)
        ),
        Leg(
            label: "sneak",
            gait: .sneak,
            input: CameraInput(moveForward: 1, sneak: true, dt: step)
        )
    ]

    // MARK: - Assertions

    /// Jump and land are edges rather than held states, so they are driven and
    /// asserted apart from the route: the capsule has to leave the ground, come
    /// back, and the graph has to be told about both.
    private func assertJumpAndLanding(
        _ harness: LocomotionDriveHarness,
        body: PlayerBody
    ) throws {
        #expect(harness.controller.isGrounded)
        let jump = harness.jump(steps: Self.secondOfSteps * 4)
        #expect(jump.leftGround)
        #expect(jump.landed)
        #expect(harness.bridge.status.raisedEvents.contains(LocomotionGraphNames.jumpUp))
        #expect(harness.bridge.status.raisedEvents.contains(LocomotionGraphNames.jumpLand))
        body.place(
            feetPosition: harness.controller.feetPosition, yaw: harness.camera.yaw
        )
        #expect(body.animation.update(at: 0) > 0)
    }

    /// Swimming is the one leg the launch cell cannot supply on its own — it is
    /// dry land — so the water surface is injected and called out as injected
    /// (`PlayerBodyFixture.swimSurfaceDepth`). Everything else in the leg is
    /// real: the gait resolution, the graph's swim state, and the body's pose.
    private func assertSwimming(
        _ harness: LocomotionDriveHarness,
        body: PlayerBody
    ) throws -> [float4x4] {
        let surface = harness.controller.feetPosition.z + PlayerBodyFixture.swimSurfaceDepth
        harness.bridge.sampleWater = { _ in surface }
        defer { harness.bridge.sampleWater = nil }
        let result = harness.run(
            input: CameraInput(moveForward: 1, dt: Self.step),
            steps: Self.secondOfSteps,
            label: "swim"
        )
        #expect(harness.bridge.status.gait == .swim)
        #expect(harness.bridge.status.isSwimming)
        #expect(harness.bridge.status.raisedEvents.contains(LocomotionGraphNames.swimStart))
        #expect(result.distance > 0)
        body.place(
            feetPosition: harness.controller.feetPosition, yaw: harness.camera.yaw
        )
        #expect(body.animation.update(at: 0) > 0)
        harness.note("swim: injected surface \(surface), distance \(result.distance)")
        return PlayerBodyFixture.palettes(of: body)
    }

    /// Every gait has to look different. Two gaits that produce identical bone
    /// palettes would mean the graph never left the state it started in, which
    /// is exactly the failure a bound-but-inert graph produces.
    private func assertEveryGaitPosedDifferently(
        _ seen: [LocomotionGait: [float4x4]],
        note: (String) -> Void
    ) {
        let gaits = seen.keys.sorted { $0.rawValue < $1.rawValue }
        note("gaits posed: \(gaits.map(\.rawValue))")
        #expect(gaits.count == Set(Self.route.map(\.gait)).union([.swim]).count)
        for (index, first) in gaits.enumerated() {
            for second in gaits.dropFirst(index + 1) {
                #expect(
                    seen[first] != seen[second],
                    "\(first.rawValue) and \(second.rawValue) posed identically"
                )
            }
        }
    }

    /// What the graph could not do, so a run that poses badly says why in the
    /// trace instead of only failing an expectation.
    private static func tallyLines(_ graph: PlayerBehaviorGraph) -> [String] {
        let tally = graph.instance.tally
        return [
            "clips loaded \(graph.clips.loadedCount), missed \(graph.clips.missCount)",
            "behavior files indexed \(graph.referenceSource.indexedCount), "
                + "resolved \(graph.instance.referencedGraphs.keys.sorted())",
            "unresolved clips \(tally.unresolvedClipTotal): "
                + "\(tally.unresolvedClips.keys.sorted().prefix(12))",
            "unevaluated generators \(tally.unevaluatedGeneratorTotal): "
                + "\(tally.unevaluatedGenerators)",
            "partial generators \(tally.partialGeneratorTotal): \(tally.partialGenerators)",
            "passthrough modifiers \(tally.passthroughModifierTotal): "
                + "\(tally.passthroughModifiers)",
            "feature gaps \(tally.featureGapTotal): \(tally.featureGaps)",
            "unapplied bindings \(tally.unappliedBindingTotal)",
            "recent graph events \(graph.instance.events.active.compactMap(\.name))",
            "undecodable objects \(tally.undecodableObjectTotal): \(tally.undecodableObjects)"
        ]
    }

    private static func activeStateNames(_ graph: PlayerBehaviorGraph) -> [String] {
        graph.instance.activeStates.compactMap(\.stateName)
    }
}
