// Census aggregation over synthetic collision models. The real-data sweep is
// NIFDynamicsCensusRealDataTests; this pins the arithmetic without an install.

import Foundation
@testable import opensky
import simd
import Testing

struct NIFDynamicsCensusTests {
    @Test func aggregatesMotionSystemsLayersAndMasses() throws {
        var census = NIFDynamicsCensus()
        try census.record(model: model(motionSystem: 7, mass: 0, layer: 1), path: "static.nif")
        try census.record(model: model(motionSystem: 4, mass: 8, layer: 4), path: "clutter.nif")
        try census.record(model: model(motionSystem: 4, mass: 250, layer: 4), path: "crate.nif")

        #expect(census.modelCount == 3)
        #expect(census.collisionBearingModelCount == 3)
        #expect(census.bodyCount == 3)
        #expect(census.motionSystemCounts == [7: 1, 4: 2])
        #expect(census.layerCounts == [1: 1, 4: 2])
        #expect(census.carrierCounts == ["bhkCollisionObject": 3])
        #expect(census.simulatedBodyCount == 2)
        #expect(census.zeroMassBodyCount == 1)
        #expect(census.masslessSimulatedBodyCount == 0)
        #expect(census.mass.bodyCount == 2)
        #expect(census.mass.minimum == 8)
        #expect(census.mass.maximum == 250)
        #expect(census.mass.mean == 129)
        // 8 kg falls in the 1-10 decade, 250 kg in the 100-1000 decade.
        #expect(census.mass.decades == [0: 1, 2: 1])
    }

    /// A dynamic motion system over zero mass is the combination an integrator
    /// divides by, so it gets its own counter rather than hiding in the total.
    @Test func countsMasslessDynamicBodiesSeparately() throws {
        var census = NIFDynamicsCensus()
        try census.record(model: model(motionSystem: 1, mass: 0, layer: 4), path: "odd.nif")
        #expect(census.simulatedBodyCount == 0)
        #expect(census.masslessSimulatedBodyCount == 1)
        #expect(census.mass.bodyCount == 0)
        #expect(census.mass.mean == nil)
    }

    @Test func recordsLoadFailuresWithoutBodies() {
        var census = NIFDynamicsCensus()
        census.record(loadFailure: "unreadable header", path: "broken.nif")
        #expect(census.modelCount == 1)
        #expect(census.collisionBearingModelCount == 0)
        #expect(census.loadFailures == ["broken.nif: unreadable header"])
    }

    private func model(
        motionSystem: UInt8,
        mass: Float,
        layer: UInt8
    ) throws -> NIFCollisionModel {
        var dynamics = NIFCollisionFixture.Dynamics()
        dynamics.mass = mass
        return try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(
                prefix: NIFFixture.avObjectPrefix(collisionRef: 1)
            )),
            .init("bhkCollisionObject", NIFCollisionFixture.collisionObject(body: 2)),
            .init("bhkRigidBody", NIFCollisionFixture.rigidBody(
                shape: 3,
                rigidLayer: layer,
                motionSystem: motionSystem,
                dynamics: dynamics
            )),
            .init("bhkSphereShape", NIFCollisionFixture.sphere(radius: 1))
        ])).collisionModel()
    }
}
