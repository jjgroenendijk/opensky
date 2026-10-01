// Offscreen render of the first-person arms on the real install. The arms draw
// with a weapon in idle, walk, and sprint, and each state differs. First person
// draws the arms and not the body, third person the reverse, and switching back
// gives the same frame byte for byte. Arms with a weapon differ from arms
// without one. Captures stay in gitignored `logs/`.

import CoreGraphics
import Foundation
import ImageIO
import Metal
import MetalKit
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import simd
import TagsTesting
import Testing
import UniformTypeIdentifiers

@Suite(.tags(.gpu))
struct FirstPersonRenderRealDataTests {
    static let size = 640

    /// `ArmorIronCuirass` and `IronSword` — the same two records the M12
    /// equipment acceptance equips, so what is on the arms here is what that
    /// test already proved resolves.
    private static let ironCuirass = FormID(0x0001_2E49)
    private static let ironSword = FormID(0x0001_2EB7)

    @Test(.enabled(if: RealDataEnvironment.canRender))
    @MainActor
    func drawsTheArmsInFirstPersonOnly() throws {
        let device = try #require(RealDataEnvironment.device)
        let root = try #require(RealDataEnvironment.dataRoot)
        let assembled = try PlayerBodyFixture.assemble(
            device: device, root: root, equipped: [Self.ironCuirass, Self.ironSword]
        )
        let scene = try assembled.builder.buildFirstRenderCell()
        let bounds = try #require(scene.bounds, "no world bounds — nothing drew")
        let terrain = try #require(LocomotionRealTerrain.terrainField(root: root))
        let feet = LocomotionRealTerrain.startPosition(on: terrain)
        let renderer = try Self.renderer(device: device, scene: scene, bounds: bounds)
        var report: [String] = []

        Self.assertRigIsUsable(assembled.arms, report: &report)

        Self.frameFirstPerson(renderer, feet: feet)
        let empty = try Self.frame(renderer)

        try renderer.setPlayerBody(assembled.body)
        try renderer.setPlayerFirstPersonRig(assembled.arms)
        Self.drive(assembled, feet: feet, input: CameraInput(dt: 1.0 / 120))
        Self.place(assembled, renderer: renderer, feet: feet)

        let idle = try Self.frame(renderer)
        let armPixels = Self.changedPixels(empty, idle)
        report.append("first person idle vs no arms: \(armPixels) changed pixels")
        #expect(armPixels > 0, "the arms drew nothing in first person")

        try Self.assertStatesDiffer(
            assembled,
            renderer: renderer,
            feet: feet,
            idle: idle,
            report: &report
        )
        try Self.assertModeSwitchCrossCheck(
            assembled,
            renderer: renderer,
            feet: feet,
            report: &report
        )
        try Self.assertEquipmentReachesTheArms(
            device: device, root: root, renderer: renderer, feet: feet, report: &report
        )

        try PlayerBodyFixture.write(
            report.joined(separator: "\n") + "\n", to: "first-person-render.log"
        )
        try Self.writePNG(idle, name: "first-person-arms.png")
        // The bind-pose capture shows whether the arms are misplaced or only
        // show the skinning defect the third-person body shares.
        renderer.actorAnimationsEnabled = false
        try Self.writePNG(Self.frame(renderer), name: "first-person-arms-bind-pose.png")
        renderer.actorAnimationsEnabled = true
    }

    // MARK: - Assertions

    /// The rig has to carry the bone the eye rides and some geometry to hang on
    /// it, or nothing measured afterwards is measuring what it claims to.
    private static func assertRigIsUsable(
        _ arms: PlayerFirstPersonRig,
        report: inout [String]
    ) {
        #expect(
            arms.cameraBoneIndex != nil,
            "the first-person rig declares no \(FirstPersonCamera.cameraBoneName)"
        )
        report.append("arm meshes: \(arms.assembly.models.count)")
        for model in arms.assembly.models {
            report.append("  \(model.path)")
        }
        report.append("dropped pieces: \(droppedPieces(arms))")
        for skip in arms.assembly.skips {
            report.append("  skip \(String(describing: skip))")
        }
        #expect(!arms.assembly.models.isEmpty, "the arms assembled no geometry")
    }

    /// Idle, walk and sprint have to reach three different frames. Equal frames
    /// would mean the first-person graph is stepped but not consumed.
    @MainActor
    private static func assertStatesDiffer(
        _ assembled: PlayerBodyFixture.Assembled,
        renderer: Renderer,
        feet: SIMD3<Float>,
        idle: [UInt8],
        report: inout [String]
    ) throws {
        var frames: [String: [UInt8]] = ["idle": idle]
        for (name, input) in [
            ("walk", CameraInput(moveForward: 1, dt: 1.0 / 120)),
            ("sprint", CameraInput(moveForward: 1, sprint: true, dt: 1.0 / 120))
        ] {
            for _ in 0 ..< LocomotionDriveHarness.secondOfSteps {
                drive(assembled, feet: feet, input: input)
            }
            place(assembled, renderer: renderer, feet: feet)
            frames[name] = try frame(renderer)
            report.append(
                "\(name) vs idle: \(changedPixels(idle, frames[name] ?? [])) changed pixels"
            )
        }
        #expect(frames["walk"] != idle, "walking left the arms in the idle pose")
        #expect(frames["sprint"] != frames["walk"], "sprinting matched walking")
    }

    /// First person, third person, and first person again, without stepping the
    /// graph. The mode is the only change, so the last frame must match the
    /// first byte for byte. The graph is stateful, so it is not driven again.
    @MainActor
    private static func assertModeSwitchCrossCheck(
        _ assembled: PlayerBodyFixture.Assembled,
        renderer: Renderer,
        feet: SIMD3<Float>,
        report: inout [String]
    ) throws {
        place(assembled, renderer: renderer, feet: feet)
        #expect(renderer.areFirstPersonArmsVisible)
        #expect(!renderer.isPlayerBodyVisible)
        let firstPerson = try frame(renderer)

        renderer.setMovementMode(.thirdPerson)
        #expect(!renderer.areFirstPersonArmsVisible)
        #expect(renderer.isPlayerBodyVisible)
        let thirdPerson = try frame(renderer)
        report.append(
            "third person vs first person: "
                + "\(changedPixels(firstPerson, thirdPerson)) changed pixels"
        )
        #expect(thirdPerson != firstPerson, "the camera mode changed nothing")

        renderer.setMovementMode(.walk)
        #expect(renderer.areFirstPersonArmsVisible)
        #expect(!renderer.isPlayerBodyVisible)
        let returned = try frame(renderer)
        #expect(returned == firstPerson, "the mode round trip changed the frame")
        report.append("mode round trip: byte-identical")

        // Fly shows the body too, so a developer can look at the character; it
        // never shows the arms.
        renderer.setMovementMode(.fly)
        #expect(!renderer.areFirstPersonArmsVisible)
        #expect(renderer.isPlayerBodyVisible)
        renderer.setMovementMode(.walk)
    }

    /// Equipping reaches both rigs: two rigs assembled from the same install at
    /// the same pose, one holding a weapon and one not, produce different arms.
    ///
    /// Both sides are freshly assembled and stepped identically, so the only
    /// difference between the two frames is the equipped set.
    @MainActor
    private static func assertEquipmentReachesTheArms(
        device: MTLDevice,
        root: GameDataRoot,
        renderer: Renderer,
        feet: SIMD3<Float>,
        report: inout [String]
    ) throws {
        var frames: [[UInt8]] = []
        for equipped in [[Self.ironCuirass, Self.ironSword], [Self.ironCuirass]] {
            let fresh = try PlayerBodyFixture.assemble(
                device: device, root: root, equipped: equipped
            )
            drive(fresh, feet: feet, input: CameraInput(dt: 1.0 / 120))
            try renderer.setPlayerBody(fresh.body)
            try renderer.setPlayerFirstPersonRig(fresh.arms)
            place(fresh, renderer: renderer, feet: feet)
            try frames.append(frame(renderer))
            report.append(
                "equipped \(equipped.count) item(s): "
                    + "\(fresh.arms.assembly.models.count) arm meshes"
            )
        }
        let changed = changedPixels(frames[0], frames[1])
        report.append("armed vs unarmed arms: \(changed) changed pixels")
        #expect(changed > 0, "removing the weapon changed nothing on the arms")
    }
}
