// M15 acceptance, pixel half: weapon draw and swing change the drawn frame, and
// the advanced frame is byte-identical to one built at that state. Arrows in
// flight and ragdolls are not drawn on the player rig, so `CombatAcceptanceTests`
// covers them with numbers (docs/tools/sidebar-acceptance.md). Needs Metal 4
// and the install; frames go to gitignored `logs/`.

import Foundation
import Metal
import MetalKit
@testable import OpenSkyActorsInterface
@testable import OpenSkyCombat
@testable import OpenSkyCombatInterface
@testable import OpenSkyGameData
@testable import OpenSkyPhysics
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import simd
import Testing

/// The three frames one player's sequence produces, named rather than tupled
/// because the strict-lint tuple cap is two and because a caller comparing
/// `drawn` against `idle` should not be counting positions.
private struct CombatRenderPoses {
    let idle: [UInt8]
    let drawn: [UInt8]
    let swinging: [UInt8]
}

/// The renderer, the spot on the terrain, and the install one render run is
/// bound to, passed as one value so the assertion helpers stay inside the
/// strict-lint parameter cap — the same shape `LocomotionAcceptanceRenderTests` uses.
@MainActor
private struct CombatRenderStage {
    let renderer: Renderer
    let feet: SIMD3<Float>
    let settings: CombatSettings
}

struct CombatAcceptanceRenderTests {
    /// How many pixels a state change has to move before it counts as visible.
    /// The same floor `LocomotionAcceptanceRenderTests` uses: well above the handful a
    /// rounding difference could touch and far below a whole body's worth.
    private static let minimumChangedPixels = 200

    private static let step: Float = 1.0 / 120

    @Test(.enabled(if: RealDataEnvironment.canRender))
    @MainActor
    func drawsThePlayerFollowingItsCombatState() throws {
        let cell = try PlayerBodyFixture.stage()
        let assembled = cell.assembled
        let feet = try cell.terrainStart()
        let renderer = try cell.renderer()
        try renderer.setPlayerBody(assembled.body)
        try renderer.setPlayerFirstPersonRig(assembled.arms)
        var report: [String] = []

        let settings = CombatSettings.resolve(store: GameSettingLoader.load(root: cell.root))
        let stage = CombatRenderStage(
            renderer: renderer, feet: feet, settings: settings
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
        let second = try PlayerBodyFixture.assemble(device: cell.device, root: cell.root)
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

    /// Standing, weapon drawn, and partway through a swing, with one melee
    /// runtime, because the draw state decides whether a swing is allowed.
    @MainActor
    private static func poses(
        _ assembled: PlayerBodyFixture.Assembled,
        stage: CombatRenderStage
    ) throws -> CombatRenderPoses {
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
        return CombatRenderPoses(idle: idle, drawn: drawn, swinging: swinging)
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
        stage: CombatRenderStage,
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
    /// way `LocomotionAcceptanceRenderTests` frames its captures.
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
