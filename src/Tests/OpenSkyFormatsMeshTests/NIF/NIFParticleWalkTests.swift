// Which particle systems the scene graph walk finds: it enters a switch node like the
// mesh walk (docs/formats/nif-particles.md#from-scene-graph-to-particle-system).

import Foundation
@testable import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import simd
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

    @Test func aSystemKnowsTheNodesAboveItAndItsInheritObject() throws {
        let bone = NIFFixture.niNode(
            prefix: NIFFixture.avObjectPrefix(nameIndex: 1, translation: [5, 0, 0]),
            children: [2]
        )
        let file = try NIFFile(data: NIFFixture.file(
            blocks: [
                NIFFixture.Block("NiNode", NIFFixture.niNode(
                    prefix: NIFFixture.avObjectPrefix(nameIndex: 0), children: [1]
                )),
                NIFFixture.Block("NiNode", bone),
                NIFFixture.Block("NiParticleSystem", NIFParticleFixture.particleSystemSSE(
                    dataRef: -1, modifierRefs: [3]
                )),
                NIFFixture.Block(
                    "BSPSysInheritVelocityModifier",
                    NIFParticleParameterFixture.inheritVelocity(
                        chance: 100, multiplier: 1, objectRef: 1
                    )
                )
            ],
            strings: ["Scene", "WeaponTip"],
            roots: [0]
        ))
        let system = try #require(try file.particleSystems().first)
        #expect(system.ancestorNodes == ["weapontip", "scene"])
        guard case let .inheritVelocity(inherit) = system.modifiers.first?.kind else {
            Issue.record("no inherit velocity modifier")
            return
        }
        #expect(inherit.objectNodes == ["weapontip", "scene"])
        #expect(simd_length(inherit.objectOrigin) < 1e-5)
    }

    @Test func aLightningControllerBecomesABoltAtItsTargetShape() throws {
        let file = try NIFFile(data: NIFFixture.file(
            blocks: [
                NIFFixture.Block("NiNode", NIFFixture.niNode(children: [1])),
                NIFFixture.Block("NiNode", NIFFixture.niNode(
                    prefix: NIFFixture.avObjectPrefix(controllerRef: 2, translation: [0, 0, 10])
                )),
                NIFFixture.Block(
                    "BSProceduralLightningController",
                    NIFParticleParameterFixture.lightningController(
                        targetRef: 1, subdivisions: 4, branches: 2, length: 512, width: 16
                    )
                )
            ],
            roots: [0]
        ))
        let bolt = try #require(try file.particleSystems().first { $0.lightning != nil })
        #expect(bolt.lightning?.length == 512)
        #expect(bolt.lightning?.subdivisions == 4)
        #expect(bolt.lightning?.branches == 2)
        #expect(bolt.worldTransform.columns.3.z == 10)
    }

    private static func file(underNode prefix: Data, strings: [String] = []) throws -> NIFFile {
        let system = NIFParticleFixture.particleSystemSSE(dataRef: -1)
        return try NIFFile(data: NIFFixture.file(
            blocks: [
                NIFFixture.Block("NiNode", NIFFixture.niNode(children: [1])),
                NIFFixture.Block("NiNode", NIFFixture.niNode(prefix: prefix, children: [2])),
                NIFFixture.Block("NiParticleSystem", system),
                // Next controller -1, then flags, timing, and target.
                NIFFixture.Block(
                    "NiVisController",
                    Data([0xFF, 0xFF, 0xFF, 0xFF]) + Data(count: 22)
                )
            ],
            strings: strings,
            roots: [0]
        ))
    }

    @Test func aSystemUnderAHiddenNodeIsDropped() throws {
        let shown = try Self.file(underNode: NIFFixture.avObjectPrefix(flags: 0xE))
        #expect(try shown.particleSystems().count == 1)
        let hidden = try Self.file(underNode: NIFFixture.avObjectPrefix(flags: 0xF))
        #expect(try hidden.particleSystems().isEmpty)
    }

    @Test func aSystemUnderAnEditorMarkerIsDropped() throws {
        let file = try Self.file(
            underNode: NIFFixture.avObjectPrefix(nameIndex: 0), strings: ["EditorMarker"]
        )
        #expect(try file.particleSystems().isEmpty)
    }

    /// A hidden node that a controller or a behaviour graph can show keeps its systems.
    @Test func aHiddenNodeThatCanBeShownLaterKeepsItsSystem() throws {
        let controlled = try Self.file(
            underNode: NIFFixture.avObjectPrefix(controllerRef: 3, flags: 0xF)
        )
        #expect(try controlled.particleSystems().count == 1)
        let graphShown = try Self.file(
            underNode: NIFFixture.avObjectPrefix(nameIndex: 0, flags: 0xF),
            strings: ["Sparks", "hkVis:Sparks"]
        )
        #expect(try graphShown.particleSystems().count == 1)
    }

    @Test func aLightningBoltUnderAHiddenNodeIsDropped() throws {
        let file = try NIFFile(data: NIFFixture.file(
            blocks: [
                NIFFixture.Block("NiNode", NIFFixture.niNode(
                    prefix: NIFFixture.avObjectPrefix(flags: 0xF), children: [1]
                )),
                NIFFixture.Block("NiNode", NIFFixture.niNode(
                    prefix: NIFFixture.avObjectPrefix(controllerRef: 2)
                )),
                NIFFixture.Block(
                    "BSProceduralLightningController",
                    NIFParticleParameterFixture.lightningController(
                        targetRef: 1, subdivisions: 4, branches: 2, length: 512, width: 16
                    )
                )
            ],
            roots: [0]
        ))
        #expect(try file.particleSystems().isEmpty)
    }
}
