// Where a decoded body lands when a cell is built (issue #193): the movable
// half of a NIF goes to the dynamic world and out of the immutable set, and
// the census's discriminator — a positive mass, not the motion byte alone —
// is what decides. Synthetic ESM + NIF bytes only; no game content.

import Metal
@testable import opensky
import simd
import Testing

extension CellSceneBuilderTests {
    /// Mass 12 kg with `MO_SYS_BOX_INERTIA`: a barrel, not a wall.
    private static var movableDynamics: NIFCollisionFixture.Dynamics {
        var dynamics = NIFCollisionFixture.Dynamics()
        dynamics.mass = 12
        dynamics.friction = 0.6
        dynamics.restitution = 0.3
        dynamics.linearDamping = 0.1
        dynamics.angularDamping = 0.05
        return dynamics
    }

    @Test(.enabled(if: Self.hasDevice))
    func aMovableBodyLeavesTheStaticSetAndJoinsTheDynamicWorld() throws {
        try writeLooseFile(
            "meshes/clutter/barrel.nif",
            Self.clutterNIF(motionSystem: 4, dynamics: Self.movableDynamics)
        )
        let device = try #require(Self.device)
        let builder = try makeBuilder(
            pluginData: plugin(
                temporaryRefs: refrRecord(
                    formID: 0x200, base: 0x100, position: SIMD3(100, 200, 300)
                ),
                statRecords: statRecord(formID: 0x100, modelPath: "clutter\\barrel.nif")
            ),
            device: device
        )
        builder.simulatesDynamicBodies = true

        let scene = try builder.buildScene(
            worldspaceEditorID: "Tamriel", gridX: 6, gridY: -2
        )

        #expect(scene.staticCollision.shapes.isEmpty)
        #expect(scene.dynamicBodies.count == 1)
        let body = try #require(scene.dynamicBodies.first)
        #expect(body.reference == FormID(0x200))
        #expect(body.originPosition == SIMD3(100, 200, 300))
        #expect(body.definition.mass == 12)
        #expect(abs(body.definition.friction - 0.6) < 1e-5)
        #expect(abs(body.definition.restitution - 0.3) < 1e-5)
        // The sphere's radius converts out of Havok metres like every other
        // length in this format layer.
        #expect(abs(body.definition.boundingRadius - NIFCollisionModel.havokToEngineScale) < 0.01)
    }

    /// The draw list has to be able to find the reference again, because the
    /// matrix baked here stops being where the object is the moment the solver
    /// touches it (issue #193). Every other placement in the world keeps the
    /// zero, and that zero is what makes the substitution free for them.
    @Test(.enabled(if: Self.hasDevice))
    func asimulatedReferenceTagsTheDrawInstancesItPlaces() throws {
        try writeLooseFile(
            "meshes/clutter/barrel.nif",
            drawableClutterNIF(dynamics: Self.movableDynamics)
        )
        let device = try #require(Self.device)
        let builder = try makeBuilder(
            pluginData: plugin(
                temporaryRefs: refrRecord(
                    formID: 0x200, base: 0x100, position: SIMD3(100, 200, 300)
                ),
                statRecords: statRecord(formID: 0x100, modelPath: "clutter\\barrel.nif")
            ),
            device: device
        )
        builder.simulatesDynamicBodies = true

        let simulated = try builder.buildScene(
            worldspaceEditorID: "Tamriel", gridX: 6, gridY: -2
        )

        let tagged = Self.drawInstances(of: simulated).map(\.referenceFormID)
        #expect(!tagged.isEmpty)
        #expect(tagged.allSatisfy { $0 == 0x200 })

        // The same cell built without the routing draws the same geometry with
        // nothing to substitute, because nothing simulates it.
        builder.simulatesDynamicBodies = false
        let unsimulated = try builder.buildScene(
            worldspaceEditorID: "Tamriel", gridX: 6, gridY: -2
        )
        #expect(Self.drawInstances(of: unsimulated).allSatisfy { $0.referenceFormID == 0 })
    }

    private static func drawInstances(of scene: CellScene) -> [DrawInstance] {
        (scene.renderScene.opaque + scene.renderScene.alphaTested).flatMap(\.instances)
    }

    /// The census finding that the motion byte alone does not separate movable
    /// from static: vanilla exports walls as `MO_SYS_BOX_STABILIZED` with zero
    /// mass, and a consumer that trusts it would simulate the world.
    @Test(.enabled(if: Self.hasDevice))
    func aMasslessBodyStaysStaticWhateverItsMotionSystemSays() throws {
        try writeLooseFile(
            "meshes/clutter/wall.nif",
            Self.clutterNIF(motionSystem: 5, dynamics: NIFCollisionFixture.Dynamics())
        )
        let device = try #require(Self.device)
        let builder = try makeBuilder(
            pluginData: plugin(
                temporaryRefs: refrRecord(formID: 0x200, base: 0x100),
                statRecords: statRecord(formID: 0x100, modelPath: "clutter\\wall.nif")
            ),
            device: device
        )
        builder.simulatesDynamicBodies = true

        let scene = try builder.buildScene(
            worldspaceEditorID: "Tamriel", gridX: 6, gridY: -2
        )

        #expect(scene.dynamicBodies.isEmpty)
        #expect(scene.staticCollision.stats.shapeCount == 1)
    }

    /// A collision-only build has no runtime reference index behind it, so a
    /// body has no key to be registered under and stays static rather than
    /// being dropped from the world entirely.
    @Test(.enabled(if: Self.hasDevice))
    func aReferenceWithNoRuntimeKeyKeepsItsStaticShapes() throws {
        try writeLooseFile(
            "meshes/clutter/barrel.nif",
            Self.clutterNIF(motionSystem: 4, dynamics: Self.movableDynamics)
        )
        let device = try #require(Self.device)
        let builder = try makeBuilder(
            pluginData: plugin(
                temporaryRefs: refrRecord(formID: 0x200, base: 0x100),
                statRecords: statRecord(formID: 0x100, modelPath: "clutter\\barrel.nif")
            ),
            device: device
        )
        builder.simulatesDynamicBodies = true

        let collision = try builder.buildStaticCollision(
            worldspaceEditorID: "Tamriel", gridX: 6, gridY: -2
        )

        #expect(collision.stats.shapeCount == 1)
    }

    /// The same movable body with geometry hanging off the node, because the
    /// claim under test is about what the *draw* list carries and a
    /// collision-only fixture places nothing to draw.
    private func drawableClutterNIF(
        dynamics: NIFCollisionFixture.Dynamics
    ) -> Data {
        NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(
                prefix: NIFFixture.avObjectPrefix(collisionRef: 2),
                children: [1]
            )),
            .init("BSTriShape", NIFFixture.bsTriShape(
                attributes: Self.staticAttributes,
                strideDwords: Self.staticStrideDwords,
                vertexRecords: [
                    SIMD3<Float>(0, 0, 0),
                    SIMD3<Float>(16, 0, 0),
                    SIMD3<Float>(0, 16, 16)
                ].map(vertexRecord(position:)),
                triangles: [0, 1, 2]
            )),
            .init("bhkCollisionObject", NIFCollisionFixture.collisionObject(body: 3)),
            .init("bhkRigidBody", NIFCollisionFixture.rigidBody(
                shape: 4, motionSystem: 4, dynamics: dynamics
            )),
            .init("bhkSphereShape", NIFCollisionFixture.sphere(radius: 1))
        ])
    }

    private static func clutterNIF(
        motionSystem: UInt8,
        dynamics: NIFCollisionFixture.Dynamics
    ) -> Data {
        NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(
                prefix: NIFFixture.avObjectPrefix(collisionRef: 1)
            )),
            .init("bhkCollisionObject", NIFCollisionFixture.collisionObject(body: 2)),
            .init("bhkRigidBody", NIFCollisionFixture.rigidBody(
                shape: 3, motionSystem: motionSystem, dynamics: dynamics
            )),
            .init("bhkSphereShape", NIFCollisionFixture.sphere(radius: 1))
        ])
    }
}
