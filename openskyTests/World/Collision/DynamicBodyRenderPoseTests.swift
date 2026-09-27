// Drawing a body where it actually is (issue #193): the rigid transform that
// carries a reference from the pose its cell build baked to the pose the
// solver has it at, the map the renderer consults, and what applying one does
// to a draw instance. No Metal here — the arithmetic is the whole claim, and
// the pixel evidence that it reaches the screen is RendererDynamicPoseTests.

@testable import opensky
import simd
import Testing

struct DynamicBodyRenderPoseTests {
    private static let cell = CellSceneLocation.interior(FormID(0x10))

    private static func placement(
        key: ReferenceKey,
        reference: FormID = FormID(0x200),
        at position: SIMD3<Float>,
        orientation: simd_quatf = .identityRotation
    ) -> DynamicBodyPlacement {
        let volume = DynamicCollisionVolume.box(halfExtents: SIMD3(repeating: 10))
            ?? .radial(first: .zero, second: .zero, radius: 10)
        return DynamicBodyPlacement(
            key: key,
            reference: reference,
            definition: DynamicBodyDefinition(volumes: [volume], mass: 20),
            originPosition: position,
            orientation: orientation
        )
    }

    private static var floorWorld: DynamicStepWorld {
        DynamicStepWorld(staticCandidates: DynamicBodyScene.query([DynamicBodyScene.floor()]))
    }

    /// The delta's whole contract: composed onto the matrix the build baked, it
    /// produces the matrix the body is at now. Asserted through a placement
    /// matrix that carries a scale, because the scale is exactly what the delta
    /// must leave alone.
    @Test
    func theDeltaCarriesTheBakedPlacementOntoTheLiveOne() throws {
        let placed = SIMD3<Float>(100, 200, 300)
        let placedRotation = SIMD3<Float>(0, 0, 0.5)
        let orientation = simd_quatf(MatrixMath.placement(
            position: .zero, rotation: placedRotation, scale: 1
        ))
        var body = DynamicBodyScene.cube(
            key: .generated(1), center: placed, orientation: orientation
        )
        let baked = MatrixMath.placement(
            position: placed, rotation: placedRotation, scale: 2.5
        )

        // Roll it a quarter turn about +X and drop it twenty units.
        let turn = simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0))
        body.position += SIMD3(0, 0, -20)
        body.orientation = turn * body.orientation
        let delta = try #require(body.instanceDelta(
            fromPlacedPosition: placed, orientation: orientation
        ))

        let expected = MatrixMath.translation(body.originPosition)
            * float4x4(body.orientation)
            * MatrixMath.scale(uniform: 2.5)
        let actual = delta * baked
        for column in 0 ..< 4 {
            #expect(simd_distance(actual[column], expected[column]) < 1e-3)
        }
    }

    /// A body sitting exactly where it was placed has nothing to say, which is
    /// what keeps the renderer's map empty in a world standing still.
    @Test
    func abodyThatHasNotMovedHasNoDelta() {
        let body = DynamicBodyScene.cube(key: .generated(1), center: SIMD3(0, 0, 50))
        #expect(body.instanceDelta(
            fromPlacedPosition: SIMD3(0, 0, 50), orientation: .identityRotation
        ) == nil)
    }

    @Test
    func theWorldPublishesEachMovedBodyUnderItsReferenceFormID() {
        var world = DynamicBodyWorld()
        world.setCell(Self.cell, placements: [
            Self.placement(key: .generated(1), reference: FormID(0x200), at: SIMD3(0, 0, 200)),
            Self.placement(key: .generated(2), reference: FormID(0x201), at: SIMD3(200, 0, 10))
        ])
        #expect(world.instanceDeltas.isEmpty)

        world.advance(by: 0.25, world: Self.floorWorld)

        // The high one is mid-fall; the low one is already on the floor. Only
        // the mover is published, and it is keyed by the REFR a draw instance
        // carries rather than by the body's own key.
        let deltas = world.instanceDeltas
        #expect(deltas[0x200] != nil)
        let fallen = deltas[0x200]?.columns.3.z ?? 0
        #expect(fallen < -1)
    }

    /// A settled body's pose reaches the scene through a cell rebuild, and the
    /// rebuild bakes it into the instance matrix. The delta has to collapse at
    /// the same moment or the object would be drawn displaced twice over.
    @Test
    func arebuildThatBakesTheRestingPoseClearsTheDelta() {
        var world = DynamicBodyWorld()
        world.setCell(Self.cell, placements: [
            Self.placement(key: .generated(1), at: SIMD3(0, 0, 200))
        ], sequence: 1)
        world.advance(by: 1.5, world: Self.floorWorld)
        let rested = world.body(for: .generated(1))?.originPosition ?? .zero
        #expect(world.instanceDeltas[0x200] != nil)

        world.setCell(Self.cell, placements: [
            Self.placement(key: .generated(1), at: rested)
        ], sequence: 2)

        #expect(world.instanceDeltas.isEmpty)
        // And the panel's reset now returns the body to the rebuilt pose rather
        // than to the one the plugin authored, which is the same fact.
        world.reset()
        #expect(world.body(for: .generated(1))?.originPosition == rested)
    }

    @Test
    func movingADrawInstanceCarriesItsMatricesAndItsCullingBounds() {
        let baked = MatrixMath.translation(SIMD3(10, 0, 0))
        let instance = DrawInstance(
            modelMatrix: baked,
            normalMatrix: MatrixMath.normalMatrix(baked),
            bounds: ModelBounds(min: SIMD3(0, -10, -10), max: SIMD3(20, 10, 10)),
            castsShadows: true,
            receivesPointLights: true,
            receivesShadows: true,
            referenceFormID: 0x200
        )
        let delta = MatrixMath.translation(SIMD3(0, 0, 90))

        let moved = instance.moved(by: delta)

        #expect(moved.modelMatrix.columns.3 == SIMD4<Float>(10, 0, 90, 1))
        #expect(moved.bounds?.min == SIMD3(0, -10, 80))
        #expect(moved.bounds?.max == SIMD3(20, 10, 100))
        #expect(moved.referenceFormID == 0x200)
        #expect(moved.castsShadows)
    }
}
