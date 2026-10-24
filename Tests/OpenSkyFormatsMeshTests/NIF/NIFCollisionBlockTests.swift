// Shape phantoms, cylinder and plane shapes, the ball-and-socket chain, and the
// breakable constraint over synthetic blocks (docs/formats/nif-collision.md).

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import simd
import Testing

@Suite(.tags(.parser))
struct NIFCollisionBlockTests {
    private let scale = NIFCollisionModel.havokToEngineScale

    @Test func shapePhantomBecomesAnInertTrigger() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(prefix: NIFFixture.avObjectPrefix(collisionRef: 1))),
            .init("bhkSPCollisionObject", NIFCollisionFixture.collisionObject(body: 2)),
            .init("bhkSimpleShapePhantom", NIFBlockFixture.shapePhantom(
                shape: 3, layer: 12, translation: SIMD3(0, 0, 1)
            )),
            .init("bhkSphereShape", NIFCollisionFixture.sphere(radius: 1))
        ]))
        let model = file.collisionModel()
        #expect(model.decodeFailures.isEmpty)
        let body = try #require(model.bodies.first)
        #expect(body.carrier == .shapePhantom)
        #expect(body.isTriggerVolume)
        #expect(!body.isPlayerSolid)
        #expect(body.dynamics.mass == 0)
        #expect(abs(body.transform.columns.3.z - scale) < 1e-3)
        #expect(body.shapes.count == 1)
    }

    /// A pressure plate's phantom stores 0 as the matrix's last float. The reference's
    /// position must still carry through, or the trigger sits at the cell origin.
    @Test func phantomMatrixKeepsTheParentTranslation() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(prefix: NIFFixture.avObjectPrefix(collisionRef: 1))),
            .init("bhkSPCollisionObject", NIFCollisionFixture.collisionObject(body: 2)),
            .init("bhkSimpleShapePhantom", NIFBlockFixture.shapePhantom(
                shape: 3, layer: 12, translation: .zero, w: 0
            )),
            .init("bhkSphereShape", NIFCollisionFixture.sphere(radius: 1))
        ]))
        let body = try #require(file.collisionModel().bodies.first)
        var reference = matrix_identity_float4x4
        reference.columns.3 = SIMD4(100, 200, 300, 1)
        let placed = reference * body.transform
        #expect(placed.columns.3 == SIMD4(100, 200, 300, 1))
    }

    @Test func cylinderBecomesAClosedPrism() throws {
        let cylinder = try #require(decode("bhkCylinderShape", NIFBlockFixture.cylinder(
            first: SIMD3(0, 0, -1), second: SIMD3(0, 0, 1), radius: 0.5
        )) as? NIFCylinderShape)
        #expect(abs(cylinder.radius - 0.5 * scale) < 1e-3)
        guard case let .convexVertices(vertices, hull) = cylinder.geometry else {
            Issue.record("expected a convex prism, got \(cylinder.geometry)")
            return
        }
        #expect(vertices.count == 2 * NIFCylinderShape.sides)
        #expect(!hull.isEmpty && hull.count % 3 == 0)
        #expect(vertices.allSatisfy { abs(simd_length($0.xy(0)) - cylinder.radius) < 1e-2 })
    }

    @Test func planeIsClippedToItsBox() throws {
        let plane = try #require(decode("bhkPlaneShape", NIFBlockFixture.plane(
            normal: SIMD3(0, 0, 1), constant: 0.5, halfExtents: SIMD3(1, 2, 3), center: .zero
        )) as? NIFPlaneShape)
        guard case let .triangleSoup(vertices, indices) = plane.geometry else {
            Issue.record("expected two triangles, got \(plane.geometry)")
            return
        }
        #expect(indices.count == 6)
        #expect(vertices.allSatisfy { abs($0.z - 0.5 * scale) < 1e-2 })
        #expect(vertices.allSatisfy { abs($0.x) <= scale + 1e-3 && abs($0.y) <= 2 * scale + 1e-3 })
    }

    @Test func chainAndBreakableJoinTheBodies() throws {
        let model = try NIFFile(data: chainFile()).collisionModel()
        #expect(model.decodeFailures.isEmpty)
        #expect(model.unsupportedReachableBlocks.isEmpty)
        let constraints = model.constraints
        #expect(constraints.count == 3)
        let chain = constraints.filter { $0.block == 7 }
        #expect(chain.map(\.link) == [0, 1])
        #expect(chain.map(\.entityA) == [3, 4])
        #expect(chain.map(\.entityB) == [4, 5])
        let breakable = try #require(constraints.first { $0.block == 8 })
        #expect(breakable.type == .ballAndSocket)
        guard case let .breakable(threshold, removed, _) = breakable.data else {
            Issue.record("expected a breakable joint, got \(breakable.data)")
            return
        }
        #expect(threshold == 40)
        #expect(removed)
    }

    private func decode(_ type: String, _ data: Data) throws -> Any? {
        let file = try NIFFile(data: NIFFixture.file(blocks: [.init(type, data)]))
        return try NIFBlockDecoders.decode(file.blocks[0], header: file.header)
    }

    /// Root 0 holds nodes 1 and 2 and 9; bodies 3, 4, 5 share sphere 6; chain 7; breakable 8.
    private func chainFile() -> Data {
        func node(collision: Int32) -> NIFFixture.Block {
            .init(
                "NiNode",
                NIFFixture.niNode(prefix: NIFFixture.avObjectPrefix(collisionRef: collision))
            )
        }
        return NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(children: [1, 2, 9])),
            node(collision: 10),
            node(collision: 11),
            .init("bhkRigidBody", NIFCollisionFixture.rigidBody(shape: 6, constraints: [7, 8])),
            .init("bhkRigidBody", NIFCollisionFixture.rigidBody(shape: 6, constraints: [7])),
            .init("bhkRigidBody", NIFCollisionFixture.rigidBody(shape: 6)),
            .init("bhkSphereShape", NIFCollisionFixture.sphere(radius: 1)),
            .init("bhkBallSocketConstraintChain", NIFBlockFixture.ballSocketChain(
                pivots: [SIMD3(0, 0, 1), SIMD3(0, 0, -1), SIMD3(0, 1, 0), SIMD3(0, -1, 0)],
                entities: [3, 4, 5]
            )),
            .init(
                "bhkBreakableConstraint",
                NIFBlockFixture.breakable(entityA: 3, entityB: 5, threshold: 40)
            ),
            node(collision: 12),
            .init("bhkCollisionObject", NIFCollisionFixture.collisionObject(target: 1, body: 3)),
            .init("bhkCollisionObject", NIFCollisionFixture.collisionObject(target: 2, body: 4)),
            .init("bhkCollisionObject", NIFCollisionFixture.collisionObject(target: 9, body: 5))
        ])
    }
}

extension SIMD3<Float> {
    /// The vector with its z replaced.
    fileprivate func xy(_ z: Float) -> SIMD3<Float> {
        SIMD3(x, y, z)
    }
}
