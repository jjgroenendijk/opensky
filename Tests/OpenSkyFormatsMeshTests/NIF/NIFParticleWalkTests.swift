// Which particle systems the scene graph walk finds: it enters a switch node like the
// mesh walk (docs/formats/nif-particles.md#from-scene-graph-to-particle-system).

import Foundation
@testable import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct NIFParticleWalkTests {
    /// The walk enters a switch node like the mesh walk: its active child only.
    @Test func aSystemUnderTheActiveSwitchChildIsFound() throws {
        let system = NIFParticleFixture.particleSystemSSE(dataRef: -1)
        let file = try NIFFile(data: NIFFixture.file(
            blocks: [
                NIFFixture.Block("NiSwitchNode", NIFFixture.niSwitchNode(
                    children: [1, 2], activeIndex: 0
                )),
                NIFFixture.Block("NiParticleSystem", system),
                NIFFixture.Block("NiParticleSystem", system)
            ],
            roots: [0]
        ))
        #expect(try file.particleSystems().count == 1)
    }
}
