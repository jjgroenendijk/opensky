// M15 acceptance, pixel half (issue #198): the fight is drawn, the drawing
// follows the combat state, and the change is measured as changed-pixel counts
// rather than eyeballed.
//
// Three frames rather than two, for the reason `M12AcceptanceRenderTests`
// recorded and `M13` and `M14` reused: the strongest statement available is not
// "the count changed" but "the frame reached by advancing is byte-identical to
// a frame built at that state all along". Both axes the gate can measure get
// that treatment — a weapon draw, and a swing.
//
// Two of the four axes issue #198 names are deliberately *not* measured here,
// and the reason is a property of the engine rather than of this suite:
//
// * An arrow in flight has no drawn representation yet. `ProjectileRuntime`
//   simulates the flight and spawns the arrow that *lands* through
//   `ReferenceSpawnState`, so the only pixels a shot can produce are the stuck
//   arrow's, which need a cell rebuild rather than a frame
//   (docs/engine/archery.md, "Stuck arrows and the streaming lifecycle").
// * A ragdoll collapse reaches the renderer through `RenderScene.ragdollPoses`,
//   which is keyed by an ACHR's FormID and merges into that actor's animated
//   pose. The player rig this suite renders is not an ACHR and takes its pose
//   from the graph, so a collapse cannot be published onto it.
//
// Both are recorded rather than papered over, and both are covered by the
// deterministic suites instead: `M15AcceptanceTests` pins the arrow's whole
// trajectory and the ragdoll's spawn, settle and resting pose with numbers.
// The sidebar-acceptance convention makes pixel evidence optional for exactly
// this reason (docs/tools/sidebar-acceptance.md).
//
// Gated on a Metal 4 device *and* on the install, because what is being drawn
// is the user's own player mesh under the user's own animation data.
//
// Rendered frames go to gitignored `logs/`: a frame embeds the user's game art
// and is never committed (AGENTS.md "Legal & IP boundary").

import Foundation
import Metal
import MetalKit
@testable import opensky
import simd
import Testing

/// The three frames one player's sequence produces, named rather than tupled
/// because the strict-lint tuple cap is two and because a caller comparing
/// `drawn` against `idle` should not be counting positions.
private struct M15RenderPoses {
    let idle: [UInt8]
    let drawn: [UInt8]
    let swinging: [UInt8]
}

/// The renderer, the spot on the terrain, and the install one render run is
/// bound to, passed as one value so the assertion helpers stay inside the
/// strict-lint parameter cap — the same shape `M14AcceptanceRenderTests` uses.
@MainActor
private struct M15RenderStage {
    let renderer: Renderer
    let feet: SIMD3<Float>
    let settings: CombatSettings
    let device: MTLDevice
    let root: GameDataRoot
}

struct M15AcceptanceRenderTests {
    /// How many pixels a state change has to move before it counts as visible.
    /// The same floor `M14AcceptanceRenderTests` uses: well above the handful a
    /// rounding difference could touch and far below a whole body's worth.
    private static let minimumChangedPixels = 200

    private static let step: Float = 1.0 / 120

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

    @Test(.enabled(if: Self.canRun))
    @MainActor
    func drawsThePlayerFollowingItsCombatState() throws {
        let device = try #require(Self.device)
        let root = try #require(Self.dataRoot)
        let assembled = try PlayerBodyFixture.assemble(device: device, root: root)
        let scene = try assembled.builder.buildScene(
            worldspaceEditorID: FirstRenderCell.worldspaceEditorID,
            gridX: FirstRenderCell.gridX,
            gridY: FirstRenderCell.gridY
        )
        let bounds = try #require(scene.bounds, "no world bounds — nothing drew")
        let terrain = try #require(LocomotionRealTerrain.terrainField(root: root))
        let feet = LocomotionRealTerrain.startPosition(on: terrain)
        let renderer = try FirstPersonRenderRealDataTests.renderer(
            device: device, scene: scene, bounds: bounds
        )
        try renderer.setPlayerBody(assembled.body)
        try renderer.setPlayerFirstPersonRig(assembled.arms)
        var report: [String] = []

        let settings = CombatSettings.resolve(store: GameSettingLoader.load(root: root))
        let stage = M15RenderStage(
            renderer: renderer, feet: feet, settings: settings, device: device, root: root
        )
        let frames = try Self.poses(assembled, stage: stage)

        let equipped = FirstPersonRenderRealDataTests.changedPixels(
            frames.idle, frames.drawn
        )
        report.append("weapon drawn vs idle: \(equipped) changed pixels")
        #expect(
            equipped >= Self.minimumChangedPixels,
            "drawing the weapon changed only \(equipped) pixels"
        )
        let changed = FirstPersonRenderRealDataTests.changedPixels(
            frames.drawn, frames.swinging
        )
        report.append("mid-swing vs weapon drawn: \(changed) changed pixels")
        #expect(changed >= Self.minimumChangedPixels, "the swing changed only \(changed) pixels")

        // The third frame: the identical sequence from a player whose graph has
        // never been stepped. Byte-identical is the strongest statement
        // available — it says the difference above is the combat state rather
        // than the republish, and that the state is reached deterministically.
        let second = try PlayerBodyFixture.assemble(device: device, root: root)
        try renderer.setPlayerBody(second.body)
        try renderer.setPlayerFirstPersonRig(second.arms)
        let again = try Self.poses(second, stage: stage)
        let residual = FirstPersonRenderRealDataTests.changedPixels(
            frames.swinging, again.swinging
        )
        report.append("second player at the same state: \(residual) changed pixels")
        #expect(
            residual == 0,
            "the same input from a fresh graph drew a different frame (\(residual) pixels)"
        )

        try PlayerBodyFixture.write(
            report.joined(separator: "\n") + "\n", to: "m15-acceptance-render.log"
        )
        try FirstPersonRenderRealDataTests.writePNG(frames.drawn, name: "m15-weapon-drawn.png")
        try FirstPersonRenderRealDataTests.writePNG(frames.swinging, name: "m15-mid-swing.png")
    }

    // MARK: - Axes

    /// The three poses one player is taken through, in one sequence with one
    /// melee runtime: standing, weapon drawn, and partway through a swing.
    ///
    /// One runtime for the whole sequence rather than one per pose, because the
    /// draw state is what decides whether the swing is allowed at all — a fresh
    /// runtime per pose would be asking a sheathed player to swing. And one
    /// sequence rather than three entry points, because the third frame's whole
    /// job is to be the same sequence run again.
    @MainActor
    private static func poses(
        _ assembled: PlayerBodyFixture.Assembled,
        stage: M15RenderStage
    ) throws -> M15RenderPoses {
        // The world is bound to a local rather than passed inline: the runtime
        // holds it weakly, exactly as every other director holds its world, so
        // an inline one is freed before the first step and the draw silently
        // never happens.
        let world = GraphBackedMeleeWorld(bridge: assembled.bridge)
        let runtime = MeleeCombatRuntime(settings: stage.settings, world: world)
        runtime.weapon = MeleeWeaponProfile(damage: 8, reach: 1, handType: .sword)

        defer { withExtendedLifetime(world) {} }
        let idle = try drive(assembled, runtime: runtime, stage: stage, seconds: 1)
        runtime.requestWeaponToggle()
        // Two seconds rather than one. The vanilla equip clip runs for about a
        // second, and `1hm_behavior.hkx` — where the attack states live — is
        // only reached once `0_master.hkx` has transitioned into
        // `Weap_Readied_State` behind it. A swing asked for before that has no
        // attack state to enter, which is the same wait
        // `MeleeCombatRealDataTests` records.
        _ = try drive(assembled, runtime: runtime, stage: stage, seconds: 1)
        let drawn = try drive(assembled, runtime: runtime, stage: stage, seconds: 1)
        #expect(runtime.state.drawState == .drawn, "the vanilla equip never finished")
        runtime.requestAttack()
        // Driven until the swing has reached its own contact frame rather than
        // for a fixed slice: the vanilla attack clip decides when that is, and
        // a fixed slice would render either a stance that has not moved yet or
        // one that has already recovered.
        let swinging = try drive(assembled, runtime: runtime, stage: stage, seconds: 1) {
            runtime.swingCount == 1
        }
        #expect(runtime.swingCount == 1, "the vanilla graph never fired a contact frame")
        return M15RenderPoses(idle: idle, drawn: drawn, swinging: swinging)
    }

    // MARK: - Driving

    /// Drives the graph for `seconds` of fixed steps at a standing pose, hands
    /// every event it fired to the melee runtime, and renders the frame it
    /// produced. Draining is what makes the runtime's own state follow the
    /// vanilla clips rather than the request.
    @MainActor
    private static func drive(
        _ assembled: PlayerBodyFixture.Assembled,
        runtime: MeleeCombatRuntime,
        stage: M15RenderStage,
        seconds: Float,
        until: () -> Bool = { false }
    ) throws -> [UInt8] {
        let steps = max(1, Int((seconds / step).rounded()))
        for _ in 0 ..< steps {
            if until() {
                break
            }
            runtime.acceptFrame(.still)
            FirstPersonRenderRealDataTests.drive(
                assembled, feet: stage.feet, input: CameraInput(dt: step)
            )
            runtime.handleGraphEvents(
                assembled.bridge.graphEvents.drain(assembled.bridge.meleeEventConsumer)
            )
        }
        return try thirdPersonFrame(stage.renderer, feet: stage.feet, place: assembled)
    }

    /// Puts the eye where third person puts it and renders one frame, the same
    /// way `M14AcceptanceRenderTests` frames its captures.
    @MainActor
    private static func thirdPersonFrame(
        _ renderer: Renderer,
        feet: SIMD3<Float>,
        place assembled: PlayerBodyFixture.Assembled
    ) throws -> [UInt8] {
        renderer.freeFlyCamera = FreeFlyCamera(
            position: feet + SIMD3(0, 0, PlayerCapsule.standard.eyeHeight),
            yaw: 0,
            pitch: 0
        )
        renderer.setMovementMode(.thirdPerson)
        renderer.freeFlyCamera.position = renderer.thirdPersonCamera.resolve(
            feetPosition: feet,
            yaw: renderer.freeFlyCamera.yaw,
            pitch: renderer.freeFlyCamera.pitch,
            collisionQuery: { _ in [] }
        )
        FirstPersonRenderRealDataTests.place(assembled, renderer: renderer, feet: feet)
        return try FirstPersonRenderRealDataTests.frame(renderer)
    }
}
