// A cape shape read back from its GPU buffers moves as cloth: the first frame sets it up,
// and the next one lets a free vertex fall and writes the move as a position delta.
// See docs/engine/cape-cloth.md.

import Metal
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsMesh
import OpenSkyPhysics
@testable import OpenSkyPlayer
@testable import OpenSkyRenderResources
import OpenSkyTagsTesting
import simd
import Testing

@MainActor
@Suite(.tags(.gpu), .unlessPlanSkips(.gpu))
struct ClothPlaybackTests {
    /// Buffers only, so any Metal device will do, as on the CI runners.
    private static let device = MTLCreateSystemDefaultDevice()
    private static let columns = 3
    private static let rows = 6

    nonisolated private static var hasDevice: Bool {
        MTLCreateSystemDefaultDevice() != nil
    }

    /// A strip lying almost flat, 10 units apart, each row 1 lower than the last. The
    /// first four rows are the 12 pins, so the last two can swing down.
    private static var positions: [SIMD3<Float>] {
        (0 ..< rows).flatMap { row in
            (0 ..< columns).map { SIMD3(Float($0) * 10, Float(row) * 10, -Float(row)) }
        }
    }

    private static var indices: [UInt16] {
        (0 ..< rows - 1).flatMap { row in
            (0 ..< columns - 1).flatMap { column -> [UInt16] in
                let top = UInt16(row * columns + column)
                let below = top + UInt16(columns)
                return [top, below, top + 1, top + 1, below, below + 1]
            }
        }
    }

    private static func playback(device: any MTLDevice) throws -> ClothPlayback {
        let mesh = try RenderMesh(device: device, mesh: Mesh(
            name: ClothPlayback.shapeName, transform: matrix_identity_float4x4,
            positions: positions, normals: [], tangents: [], bitangents: [], uvs: [],
            colors: [], indices: indices, materialSlot: 0
        ))
        return try ClothPlayback(
            actor: FormID(0x14), bone: "NPC Spine2 [Spn2]", mesh: mesh,
            deltas: FaceMorphBuffer(device: device, simulating: mesh),
            body: (radius: 16, height: 120)
        )
    }

    private static func zDelta(_ buffer: FaceMorphBuffer, vertex: Int) -> Float {
        buffer.prepare(slot: 0)
        let base = unsafe buffer.buffer.contents().advanced(by: vertex * MorphVertexLayout.stride)
        return unsafe base.assumingMemoryBound(to: Float.self)[2]
    }

    @Test(.enabled(if: Self.hasDevice))
    func theShapeReadsBackAsUploaded() throws {
        let cloth = try Self.playback(device: #require(Self.device))
        #expect(cloth.mesh.restPositions() == Self.positions)
        #expect(cloth.mesh.triangleIndices() == Self.indices)
        #expect(cloth.renderBinding[ObjectIdentifier(cloth.mesh)] === cloth.deltas)
        #expect(cloth.update(at: 0) == 0)
    }

    @Test(.enabled(if: Self.hasDevice))
    func theSecondFrameLetsAFreeVertexFall() throws {
        let cloth = try Self.playback(device: #require(Self.device))
        let far = MatrixMath.translation(SIMD3(0, 1000, 0))
        let away = cloth.bodyCapsule(actorToWorld: far, scale: 1)
        for _ in 0 ..< 2 {
            cloth.step(
                seconds: 0.033, actorToWorld: matrix_identity_float4x4,
                boneToActor: matrix_identity_float4x4, capsules: [away]
            )
        }
        let bottom = Self.positions.count - 1
        #expect(Self.zDelta(cloth.deltas, vertex: bottom) < 0)
        #expect(Self.zDelta(cloth.deltas, vertex: 0) == 0, "a pin stays put")
    }

    @Test func theBodyCapsuleTakesTheControllerRadiusAndTheBoundsHeight() {
        #expect(ClothPlayback.bodyCapsule(bounds: nil) == (18, 128))
        let wings = ClothPlayback.bodyCapsule(bounds: ModelBounds(
            min: SIMD3(-120, -10, 0), max: SIMD3(120, 10, 200)
        ))
        #expect(wings == (18, 200), "wide wings do not widen the body")
    }

    @Test(.enabled(if: Self.hasDevice))
    func theCoordinatorStepsEachPosedCapeWhileOn() throws {
        let cloth = try Self.playback(device: #require(Self.device))
        let world = FakeClothWorld(cloths: [cloth])
        let coordinator = ClothCoordinator(world: world)
        coordinator.tick(deltaTime: 0.016)
        #expect(coordinator.lastSteppedCount == 0, "an unposed actor skips its cape")
        world.frame = ClothActorFrame(
            actorToWorld: matrix_identity_float4x4, scale: 1,
            boneToActor: matrix_identity_float4x4
        )
        coordinator.tick(deltaTime: 0.016)
        #expect(coordinator.lastSteppedCount == 1)
        #expect(coordinator.readout.capes.map(\.bone) == ["NPC Spine2 [Spn2]"])
        #expect(coordinator.readout.capes.map(\.stepped) == [true])
        coordinator.tick(deltaTime: 0)
        #expect(coordinator.lastSteppedCount == 0, "a paused frame steps nothing")
        coordinator.isEnabled = false
        coordinator.tick(deltaTime: 0.016)
        #expect(coordinator.lastSteppedCount == 0)
        #expect(!coordinator.readout.isEnabled)
    }

    @Test func anEmptyWorldStepsNothing() {
        let world = FakeClothWorld(cloths: [])
        let coordinator = ClothCoordinator(world: world)
        coordinator.tick(deltaTime: 0.016)
        let readout = coordinator.readout
        #expect(readout.isEnabled && readout.steppedCount == 0 && readout.capes.isEmpty)
    }
}

private final class FakeClothWorld: ClothWorld {
    let cloths: [ClothPlayback]
    var frame: ClothActorFrame?

    init(cloths: [ClothPlayback]) {
        self.cloths = cloths
    }

    var clothPlaybacks: [ClothPlayback] {
        cloths
    }

    func clothFrame(for _: ClothPlayback) -> ClothActorFrame? {
        frame
    }
}
