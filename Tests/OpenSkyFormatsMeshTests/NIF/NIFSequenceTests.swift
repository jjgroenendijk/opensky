// Named sequences on an effect mesh: a node transform track, an effect shader float
// track whose variable sits on the controller, and the text keys. Layouts per
// NifTools nif.xml; docs/formats/nif-sequences.md.

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import simd
import Testing

@Suite(.tags(.parser))
struct NIFSequenceTests {
    private static let strings = [
        "Root", "Star", "Glow", "NiTransformController", "BSEffectShaderPropertyFloatController",
        "start", "SoundPlay.UITest"
    ]

    @Test func decodesTracksTimingAndTextKeys() throws {
        let sequences = try NIFFile(data: Self.file()).sequences()
        let sequence = try #require(sequences.first)
        #expect(sequences.count == 1)
        #expect(sequence.name == "Glow")
        #expect(sequence.timing.cycle == .loop)
        #expect(sequence.duration == 2)
        #expect(sequence.textKeys.map(\.value) == ["start", "SoundPlay.UITest"])
        #expect(sequence.textKeys.last?.time == 0.5)
        #expect(sequence.tracks.count == 2)

        guard case let .transform(channel) = sequence.tracks[0].channel else {
            Issue.record("first track is not a transform")
            return
        }
        #expect(sequence.tracks[0].target == .node("Star"))
        #expect(channel.translation(at: 1) == SIMD3(0, 0, 5))
        #expect(channel.scale(at: 1) == nil, "an #INV_FLT# pose with no keys leaves the node's own")

        guard case let .shaderFloat(variable, keys) = sequence.tracks[1].channel else {
            Issue.record("second track is not a shader float")
            return
        }
        #expect(sequence.tracks[1].target == .shaderProperty(block: 8))
        #expect(variable == 5)
        #expect(NIFKeySampler.float(keys, at: 1) == 0.75)
    }

    @Test func poseMovesTheNodeAndKeepsItsRestElsewhere() throws {
        let file = try NIFFile(data: Self.file())
        let scene = try NIFEffectScene(file: file)
        let sequence = try #require(file.sequences().first)
        let star = try #require(scene.node(named: "Star"))
        let rest = NIFEffectPose(scene: scene, playing: [])
        #expect(rest.locals[star].columns.3 == SIMD4(1, 2, 3, 1))
        let pose = NIFEffectPose(scene: scene, playing: [.init(sequence, seconds: 1)])
        #expect(pose.locals[star].columns.3 == SIMD4(0, 0, 5, 1))
    }

    /// Blocks: 0 root, 1 star, 2 and 3 its transform, 4 and 5 a float, 6 the shader
    /// controller, 7 text keys, 8 the controlled property, 9 the sequence.
    private static func file() -> Data {
        let invalid = NIFParticleControllerDecoder.invalidFloat
        var transform = Data()
        for value in [invalid, invalid, invalid, invalid, invalid, invalid, invalid, invalid] {
            transform.appendFloat32(value)
        }
        transform.appendUInt32(3)
        var transformData = Data()
        transformData.appendUInt32(0)
        transformData.appendUInt32(2)
        transformData.appendUInt32(1)
        for (time, z) in [(Float(0), Float(0)), (2, 10)] {
            transformData.appendFloat32(time)
            transformData.appendFloat32(0)
            transformData.appendFloat32(0)
            transformData.appendFloat32(z)
        }
        transformData.appendUInt32(0)
        var float = Data()
        float.appendFloat32(invalid)
        float.appendUInt32(5)
        var floatData = Data()
        floatData.appendUInt32(2)
        floatData.appendUInt32(1)
        for (time, value) in [(Float(0), Float(0.5)), (2, 1)] {
            floatData.appendFloat32(time)
            floatData.appendFloat32(value)
        }
        return NIFFixture.file(blocks: [
            NIFFixture.Block("NiNode", NIFFixture.niNode(
                prefix: NIFFixture.avObjectPrefix(nameIndex: 0), children: [1]
            )),
            NIFFixture.Block("NiNode", NIFFixture.niNode(
                prefix: NIFFixture.avObjectPrefix(nameIndex: 1, translation: [1, 2, 3])
            )),
            NIFFixture.Block("NiTransformInterpolator", transform),
            NIFFixture.Block("NiTransformData", transformData),
            NIFFixture.Block("NiFloatInterpolator", float),
            NIFFixture.Block("NiFloatData", floatData),
            NIFFixture.Block("BSEffectShaderPropertyFloatController", shaderController()),
            NIFFixture.Block("NiTextKeyExtraData", textKeys()),
            NIFFixture.Block("NiAlphaProperty", NIFFixture.niAlphaProperty(flags: 0, threshold: 0)),
            NIFFixture.Block("NiControllerSequence", sequence())
        ], strings: strings)
    }

    /// `NiTimeController`, the interpolator ref, then the controlled variable (alpha).
    private static func shaderController() -> Data {
        var out = Data()
        out.appendUInt32(0xFFFF_FFFF)
        out.appendUInt16(0x48)
        for value in [Float(1), 0, 0, 2] {
            out.appendFloat32(value)
        }
        out.appendUInt32(8)
        out.appendUInt32(4)
        out.appendUInt32(5)
        return out
    }

    private static func textKeys() -> Data {
        var out = Data()
        out.appendUInt32(0xFFFF_FFFF)
        out.appendUInt32(2)
        out.appendFloat32(0)
        out.appendUInt32(5)
        out.appendFloat32(0.5)
        out.appendUInt32(6)
        return out
    }

    private static func sequence() -> Data {
        var out = Data()
        out.appendUInt32(2)
        out.appendUInt32(2)
        out.appendUInt32(1)
        for (interpolator, controller, type) in [(UInt32(2), UInt32.max, UInt32(3)), (4, 6, 4)] {
            out.appendUInt32(interpolator)
            out.appendUInt32(controller)
            out.append(0)
            for string in [1, UInt32.max, type, UInt32.max, UInt32.max] {
                out.appendUInt32(string)
            }
        }
        out.appendFloat32(1)
        out.appendUInt32(7)
        out.appendUInt32(0)
        out.appendFloat32(1)
        out.appendFloat32(0)
        out.appendFloat32(2)
        out.appendUInt32(0xFFFF_FFFF)
        out.appendUInt32(0xFFFF_FFFF)
        out.appendUInt16(0)
        return out
    }
}
