// The graph-driven player animation (issue #189): a synthetic two-bone rig, a
// synthetic behavior graph, and the exact bone palettes the conformer writes.
// No install; the skinned mesh needs a Metal 4 device and skips without one.

import Metal
@testable import opensky
import simd
import Testing

struct PlayerBodyAnimationTests {
    private static let device: MTLDevice? = {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            device.supportsFamily(.metal4)
        else { return nil }
        return device
    }()

    private static var hasMetal4Device: Bool {
        device != nil
    }

    /// A two-bone rig: `root` at the origin, `child` 10 units up its parent.
    private static let skeleton = HKASkeleton(
        name: "test",
        bones: [
            HKABone(name: "root", lockTranslation: false),
            HKABone(name: "child", lockTranslation: false)
        ],
        parentIndices: [-1, 0],
        referencePose: [
            HKABonePose(
                translation: .zero,
                rotation: BehaviorPoseMath.identityRotation,
                scale: SIMD3(repeating: 1)
            ),
            HKABonePose(
                translation: SIMD3(0, 0, 10),
                rotation: BehaviorPoseMath.identityRotation,
                scale: SIMD3(repeating: 1)
            )
        ]
    )

    // MARK: - Pose composition

    /// The dense-pose overload composes through the parent chain: a child bone
    /// lifted in its parent's frame lands at the sum of the two translations.
    @Test
    func denseLocalPosesComposeThroughTheParentChain() throws {
        let bones = [
            Self.pose(SIMD3(5, 0, 0)),
            Self.pose(SIMD3(0, 0, 20))
        ]
        let world = try SkeletonPoseMath.worldMatrices(
            skeleton: Self.skeleton, localPoses: bones
        )
        #expect(world.count == 2)
        #expect(Self.origin(of: world[0]) == SIMD3<Float>(5, 0, 0))
        #expect(Self.origin(of: world[1]) == SIMD3<Float>(5, 0, 20))
    }

    /// A pose shorter than the rig leaves the unnamed bones at their reference
    /// pose rather than dropping them, which is what lets a graph bound to a
    /// smaller rig still pose a full skeleton.
    @Test
    func shortPosesKeepTheReferencePoseForTheRest() throws {
        let world = try SkeletonPoseMath.worldMatrices(
            skeleton: Self.skeleton, localPoses: [Self.pose(SIMD3(1, 2, 3))]
        )
        #expect(Self.origin(of: world[1]) == SIMD3<Float>(1, 2, 13))
    }

    // MARK: - Palettes

    /// The conformer writes the composed world matrix of each named bone into
    /// the palette, matched by name exactly as the M6 clip path does.
    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func theConformerWritesTheComposedPoseIntoThePalette() throws {
        let device = try #require(Self.device)
        let mesh = try Self.skinnedMesh(device: device)
        let buffer = PlayerPoseBuffer()
        let playback = PlayerAnimationPlayback(
            skeleton: Self.skeleton, pose: buffer, models: [mesh.model]
        )

        // Nothing published yet: the palette is still the bind pose.
        #expect(playback.update(at: 0) == 0)
        #expect(mesh.renderMesh.currentBoneMatrices == [
            matrix_identity_float4x4, matrix_identity_float4x4
        ])

        buffer.publish([Self.pose(SIMD3(5, 0, 0)), Self.pose(SIMD3(0, 0, 20))])
        #expect(playback.update(at: 0) == 2)
        #expect(
            mesh.renderMesh.currentBoneMatrices[0]
                == MatrixMath.translation(SIMD3(5, 0, 0))
        )
        #expect(
            mesh.renderMesh.currentBoneMatrices[1]
                == MatrixMath.translation(SIMD3(5, 0, 20))
        )
    }

    /// The wall clock does not advance this animation — the simulation does. Two
    /// updates at different times with no new pose leave the palette alone, and
    /// a new pose at the same time changes it.
    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func theSimulationClockDrivesTheConformerRatherThanTheWallClock() throws {
        let device = try #require(Self.device)
        let mesh = try Self.skinnedMesh(device: device)
        let buffer = PlayerPoseBuffer()
        let playback = PlayerAnimationPlayback(
            skeleton: Self.skeleton, pose: buffer, models: [mesh.model]
        )
        buffer.publish([Self.pose(SIMD3(1, 0, 0)), Self.pose(SIMD3(0, 0, 10))])
        #expect(playback.update(at: 0) == 2)
        let afterFirst = mesh.renderMesh.currentBoneMatrices

        // Time moved, the simulation did not.
        #expect(playback.update(at: 12.5) == 2)
        #expect(mesh.renderMesh.currentBoneMatrices == afterFirst)

        // The simulation moved, time did not.
        buffer.publish([Self.pose(SIMD3(9, 0, 0)), Self.pose(SIMD3(0, 0, 10))])
        #expect(playback.update(at: 12.5) == 2)
        #expect(mesh.renderMesh.currentBoneMatrices != afterFirst)
    }

    /// The `World > Environment` animation A/B has to be reversible: turning it
    /// off restores the bind palette, and turning it back on recomposes even
    /// though the simulation produced nothing in between.
    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func theBindPoseResetIsReversible() throws {
        let device = try #require(Self.device)
        let mesh = try Self.skinnedMesh(device: device)
        let buffer = PlayerPoseBuffer()
        let playback = PlayerAnimationPlayback(
            skeleton: Self.skeleton, pose: buffer, models: [mesh.model]
        )
        buffer.publish([Self.pose(SIMD3(7, 0, 0)), Self.pose(SIMD3(0, 0, 10))])
        playback.update(at: 0)
        let posed = mesh.renderMesh.currentBoneMatrices

        #expect(playback.resetToBindPose() == 2)
        #expect(mesh.renderMesh.currentBoneMatrices == [
            matrix_identity_float4x4, matrix_identity_float4x4
        ])

        #expect(playback.update(at: 0) == 2)
        #expect(mesh.renderMesh.currentBoneMatrices == posed)
    }

    // MARK: - Bridge publication

    /// The locomotion bridge is the only thing that steps the graph, so it is
    /// the only thing that publishes a pose. A step with a graph attached
    /// publishes; `reset` (a teleport) drops it.
    @Test
    func theBridgePublishesTheGraphPoseEveryStep() {
        let bridge = LocomotionBridge(
            configuration: .synthetic, graph: LocomotionBridgeTests.graph()
        )
        #expect(bridge.pose.bones.isEmpty)
        let revision = bridge.pose.revision
        _ = bridge.plan(LocomotionStepState(
            feetPosition: .zero,
            verticalVelocity: 0,
            isGrounded: true,
            yaw: 0,
            dt: 1.0 / 120
        ))
        #expect(bridge.pose.revision > revision)
        #expect(!bridge.pose.bones.isEmpty)

        bridge.reset()
        #expect(bridge.pose.bones.isEmpty)
    }

    /// No graph, no pose: the bodiless configuration stays a supported one.
    @Test
    func aBridgeWithNoGraphPublishesNothing() {
        let bridge = LocomotionBridge(configuration: .synthetic)
        _ = bridge.plan(LocomotionStepState(
            feetPosition: .zero,
            verticalVelocity: 0,
            isGrounded: true,
            yaw: 0,
            dt: 1.0 / 120
        ))
        #expect(bridge.pose.bones.isEmpty)
        #expect(bridge.pose.revision == 0)
    }

    // MARK: - Body transform

    /// The body faces where the camera faces. The mesh's own forward is +Y (the
    /// ACHR `angleZ` convention), so the transform turns +Y onto the camera's
    /// `(cos yaw, sin yaw)`.
    @Test
    func theBodyFacesTheCameraYaw() {
        for degrees in stride(from: Float(-180), through: 180, by: 45) {
            let yaw = MatrixMath.radians(fromDegrees: degrees)
            let transform = PlayerBody.transform(feetPosition: .zero, yaw: yaw)
            let facing = transform * SIMD4<Float>(0, 1, 0, 0)
            #expect(abs(facing.x - cosf(yaw)) < 1e-5)
            #expect(abs(facing.y - sinf(yaw)) < 1e-5)
            #expect(abs(facing.z) < 1e-5)
        }
    }

    @Test
    func theBodyStandsOnTheCapsuleFeet() {
        let feet = SIMD3<Float>(1234, -567, 89)
        let transform = PlayerBody.transform(feetPosition: feet, yaw: 1.1)
        let origin = transform * SIMD4<Float>(0, 0, 0, 1)
        #expect(abs(origin.x - feet.x) < 1e-3)
        #expect(abs(origin.y - feet.y) < 1e-3)
        #expect(abs(origin.z - feet.z) < 1e-3)
    }

    // MARK: - Fixtures

    private static func pose(_ translation: SIMD3<Float>) -> HKABonePose {
        HKABonePose(
            translation: translation,
            rotation: BehaviorPoseMath.identityRotation,
            scale: SIMD3(repeating: 1)
        )
    }

    private static func origin(of matrix: float4x4) -> SIMD3<Float> {
        SIMD3(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z)
    }

    /// One triangle skinned to the two-bone rig, with identity bind and
    /// skin-to-bone matrices so a written palette entry is exactly the composed
    /// world matrix and the assertions can be read by eye.
    @MainActor
    private static func skinnedMesh(
        device: MTLDevice
    ) throws -> (model: RenderModel, renderMesh: RenderMesh) {
        let positions: [SIMD3<Float>] = [
            SIMD3(-1, -1, 0), SIMD3(1, -1, 0), SIMD3(0, 1, 0)
        ]
        let mesh = Mesh(
            name: "body",
            transform: matrix_identity_float4x4,
            positions: positions,
            normals: Array(repeating: SIMD3(0, 0, 1), count: positions.count),
            tangents: [],
            bitangents: [],
            uvs: Array(repeating: .zero, count: positions.count),
            colors: Array(repeating: SIMD4(1, 1, 1, 1), count: positions.count),
            indices: [0, 1, 2],
            materialSlot: 0,
            skinning: MeshSkinning(
                weights: Array(repeating: SIMD4(1, 0, 0, 0), count: positions.count),
                boneIndices: Array(repeating: .zero, count: positions.count),
                bindPoseMatrices: [matrix_identity_float4x4, matrix_identity_float4x4],
                boneNames: ["root", "child"],
                skinToBoneMatrices: [matrix_identity_float4x4, matrix_identity_float4x4]
            )
        )
        let texture = try #require(device.makeTexture(descriptor: {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false
            )
            descriptor.usage = .shaderRead
            return descriptor
        }()))
        let model = try RenderModel(
            device: device,
            model: Model(
                meshes: [mesh], materials: [Self.material()], skippedShapeCount: 0
            )
        ) { _, _ in texture }
        return (model, model.meshes[0])
    }

    private static func material() -> Material {
        Material(
            diffuseTexture: nil,
            normalTexture: nil,
            uvOffset: .zero,
            uvScale: SIMD2(repeating: 1),
            alpha: 1,
            glossiness: 0,
            specularColor: .zero,
            specularStrength: 0,
            doubleSided: true,
            alphaBlend: false,
            alphaTestThreshold: nil
        )
    }
}
