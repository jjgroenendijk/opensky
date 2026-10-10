// NiPSysEmitterCtlr and NiPSysMeshEmitter decode over synthetic NIF blocks.
// Layouts per NifTools nif.xml; docs/formats/nif-particles.md.

import FormatsTesting
import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsMesh
import simd
import TagsTesting
import Testing

@Suite(.tags(.parser))
struct NIFParticleControllerTests {
    private var header: NIFHeader {
        get throws {
            var reader = BinaryReader(NIFFixture.header(bsVersion: 100))
            return try NIFHeader(reader: &reader)
        }
    }

    @Test func decodesEmitterControllerThroughChain() throws {
        let systems = try NIFFile(data: controlledFile()).particleSystems()
        let controllers = try #require(systems.first?.emitterControllers)
        try #require(controllers.count == 1)
        let controller = controllers[0]
        #expect(controller.modifierName == "Emit")
        #expect(controller.timing.cycle == .loop)
        #expect(controller.birthRate.map(\.value) == [10, 30])
        #expect(controller.active.map(\.value) == [true, false])
        #expect(controller.birthRate(at: 1) == 20)
        #expect(controller.birthRate(at: 1.6) == 0)
        #expect(controller.birthRate(at: 2.5) == 15)
    }

    @Test func decodesMeshEmitter() throws {
        let payload = NIFParticleFixture.meshEmitter(
            base: NIFParticleFixture.modifierBase(),
            emitter: NIFParticleFixture.emitterBase(),
            meshRefs: [5, 6], velocityType: 2, emitFrom: 3, axis: SIMD3(0, 0, 1)
        )
        let emitter = try NIFParticleModifierDecoder.emitter(
            typeName: "NiPSysMeshEmitter", data: payload, header: header
        )
        #expect(emitter.shape == .mesh(MeshEmitterSource(
            meshRefs: [5, 6], velocity: .direction, emitFrom: .faceSurface,
            emissionAxis: SIMD3(0, 0, 1)
        )))
    }

    @Test func cycleModesMapTimeIntoKeyRange() {
        func timing(_ cycle: ControllerCycle) -> ControllerTiming {
            ControllerTiming(cycle: cycle, frequency: 1, phase: 0, startTime: 0, stopTime: 2)
        }
        #expect(timing(.loop).controllerTime(at: 5) == 1)
        #expect(timing(.clamp).controllerTime(at: 5) == 2)
        #expect(timing(.reverse).controllerTime(at: 3) == 1)
    }

    @Test func poseValueStandsInForMissingData() throws {
        var interpolator = Data()
        interpolator.appendFloat32(12)
        interpolator.appendUInt32(0xFFFF_FFFF)
        let systems = try NIFFile(data: controlledFile(birthInterpolator: interpolator))
            .particleSystems()
        let controller = try #require(systems.first?.emitterControllers.first)
        #expect(controller.birthRate(at: 0.5) == 12)
    }

    private func controlledFile(birthInterpolator: Data? = nil) -> Data {
        var update = Data()
        update.appendUInt32(5)
        update.append(timeControllerTail())
        var emitter = Data()
        emitter.appendUInt32(0xFFFF_FFFF)
        emitter.append(timeControllerTail())
        emitter.appendUInt32(6) // interpolator
        emitter.appendUInt32(1) // modifier name "Emit"
        emitter.appendUInt32(8) // visibility interpolator
        var floatInterpolator = Data()
        floatInterpolator.appendFloat32(-3.402823466e+38)
        floatInterpolator.appendUInt32(7)
        var floatData = Data()
        floatData.appendUInt32(2)
        floatData.appendUInt32(1) // linear
        for (time, value) in [(Float(0), Float(10)), (2, 30)] {
            floatData.appendFloat32(time)
            floatData.appendFloat32(value)
        }
        var boolInterpolator = Data([2])
        boolInterpolator.appendUInt32(9)
        var boolData = Data()
        boolData.appendUInt32(2)
        boolData.appendUInt32(5) // constant
        boolData.appendFloat32(0)
        boolData.append(1)
        boolData.appendFloat32(1.5)
        boolData.append(0)
        let system = NIFParticleFixture.particleSystemSSE(
            prefix: NIFFixture.avObjectPrefix(nameIndex: 0, controllerRef: 4),
            dataRef: 2, modifierRefs: [3]
        )
        return NIFFixture.file(
            blocks: [
                NIFFixture.Block("NiNode", NIFFixture.niNode(
                    prefix: NIFFixture.avObjectPrefix(), children: [1]
                )),
                NIFFixture.Block("NiParticleSystem", system),
                NIFFixture.Block("NiPSysData", NIFParticleFixture.psysData(maxParticles: 64)),
                NIFFixture.Block("NiPSysBoxEmitter", NIFParticleFixture.boxEmitter(
                    base: NIFParticleFixture.modifierBase(nameIndex: 1),
                    emitter: NIFParticleFixture.emitterBase(),
                    width: 1, height: 1, depth: 1
                )),
                NIFFixture.Block("NiPSysUpdateCtlr", update),
                NIFFixture.Block("NiPSysEmitterCtlr", emitter),
                NIFFixture.Block("NiFloatInterpolator", birthInterpolator ?? floatInterpolator),
                NIFFixture.Block("NiFloatData", floatData),
                NIFFixture.Block("NiBoolInterpolator", boolInterpolator),
                NIFFixture.Block("NiBoolData", boolData)
            ],
            strings: ["Smoke", "Emit"],
            roots: [0]
        )
    }

    /// Flags (active, loop), frequency 1, phase 0, start 0, stop 2, target 1.
    private func timeControllerTail() -> Data {
        var out = Data()
        out.appendUInt16(0x0008)
        out.appendFloat32(1)
        out.appendFloat32(0)
        out.appendFloat32(0)
        out.appendFloat32(2)
        out.appendUInt32(1)
        return out
    }
}
