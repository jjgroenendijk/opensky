// Emitter controllers a controller manager feeds: the default sequence's keys
// replace the blend interpolators. Layouts per NifTools nif.xml (develop 292bb94);
// docs/formats/nif-particles.md.

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct NIFControllerSequenceTests {
    private static let strings = ["Smoke", "Emit", "BirthRate", "EmitterActive", "Fire", "mIdle"]

    @Test func managerFedControllerTakesTheIdleSequence() throws {
        let controller = try #require(
            NIFFile(data: managedFile()).particleSystems().first?.emitterControllers.first
        )
        #expect(controller.modifierName == "Emit")
        #expect(controller.timing.cycle == .loop)
        #expect(controller.timing.stopTime == 4)
        #expect(controller.birthRate.map(\.value) == [7])
        #expect(controller.active.map(\.value) == [true])
        #expect(controller.birthRate(at: 1) == 7)
    }

    @Test func multiTargetControllerDecodesLikeTheBase() throws {
        let controllers =
            try NIFFile(data: managedFile(controllerType: "BSPSysMultiTargetEmitterCtlr"))
                .particleSystems().first?.emitterControllers ?? []
        #expect(controllers.map(\.birthRate) == [[NIFKey(time: 0, value: 7)]])
    }

    @Test func defaultSequencePrefersIdleThenLoopThenFirst() {
        func sequence(_ name: String, _ cycle: ControllerCycle) -> NIFControllerSequenceDecoder
            .DecodedSequence
        {
            .init(name: name, cycle: cycle, feeds: [:])
        }
        let pick = NIFControllerSequenceDecoder.defaultSequence
        #expect(pick([sequence("Fire", .clamp), sequence("mIdle", .clamp)])?.name == "mIdle")
        #expect(pick([sequence("mBegin", .clamp), sequence("mLoop", .loop)])?.name == "mLoop")
        #expect(pick([sequence("Wait", .clamp), sequence("Shoot", .clamp)])?.name == "Wait")
        #expect(pick([]) == nil)
    }

    /// Blocks 6 and 7 are blend interpolators; sequence 11 ("Fire") feeds rate 99,
    /// sequence 12 ("mIdle") feeds rate 7 and on.
    private func managedFile(controllerType: String = "NiPSysEmitterCtlr") -> Data {
        var emitter = Data()
        emitter.appendUInt32(0xFFFF_FFFF)
        emitter.append(timeControllerTail(flags: 0x0028))
        emitter.appendUInt32(6)
        emitter.appendUInt32(1)
        emitter.appendUInt32(7)
        if controllerType != "NiPSysEmitterCtlr" {
            emitter.appendUInt16(4) // max emitters
            emitter.appendUInt32(0xFFFF_FFFF) // master particle system
        }
        return NIFParticleFixture.controlledSystemFile(
            emitterType: controllerType,
            emitter: emitter,
            updateTail: timeControllerTail(flags: 0x0008),
            extraBlocks: [
                NIFFixture.Block("NiBlendFloatInterpolator", Data(count: 8)),
                NIFFixture.Block("NiBlendBoolInterpolator", Data(count: 8)),
                NIFFixture.Block("NiFloatInterpolator", poseFloat(99)),
                NIFFixture.Block("NiFloatInterpolator", poseFloat(7)),
                NIFFixture.Block("NiBoolInterpolator", Data([1, 0xFF, 0xFF, 0xFF, 0xFF])),
                NIFFixture.Block("NiControllerSequence", sequence(
                    name: 4, cycle: 2, stop: 1, links: [(8, 2)]
                )),
                NIFFixture.Block("NiControllerSequence", sequence(
                    name: 5, cycle: 0, stop: 4, links: [(9, 2), (10, 3)]
                ))
            ],
            strings: Self.strings
        )
    }

    private func poseFloat(_ value: Float) -> Data {
        var out = Data()
        out.appendFloat32(value)
        out.appendUInt32(0xFFFF_FFFF)
        return out
    }

    /// nif.xml `NiControllerSequence` for 20.2.0.7, BSVER 100; every link targets block 5.
    private func sequence(
        name: UInt32,
        cycle: UInt32,
        stop: Float,
        links: [(interpolator: UInt32, id: UInt32)]
    ) -> Data {
        var out = Data()
        out.appendUInt32(name)
        out.appendUInt32(UInt32(links.count))
        out.appendUInt32(1)
        for link in links {
            out.appendUInt32(link.interpolator)
            out.appendUInt32(5)
            out.append(0)
            for string in [0, 0xFFFF_FFFF, 0xFFFF_FFFF, 0xFFFF_FFFF, link.id] as [UInt32] {
                out.appendUInt32(string)
            }
        }
        out.appendFloat32(1)
        out.appendUInt32(0xFFFF_FFFF)
        out.appendUInt32(cycle)
        out.appendFloat32(1)
        out.appendFloat32(0)
        out.appendFloat32(stop)
        out.appendUInt32(0xFFFF_FFFF)
        out.appendUInt32(0xFFFF_FFFF)
        out.appendUInt16(0)
        return out
    }

    private func timeControllerTail(flags: UInt16) -> Data {
        var out = Data()
        out.appendUInt16(flags)
        out.appendFloat32(1)
        out.appendFloat32(0)
        out.appendFloat32(0)
        out.appendFloat32(2)
        out.appendUInt32(1)
        return out
    }
}
