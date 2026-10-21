// Camera path and field of view keys, and the alpha test and float extra data
// sequence channels, over synthetic blocks (docs/formats/nif-controllers.md).

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import simd
import Testing

@Suite(.tags(.parser))
struct NIFAnimationChannelTests {
    @Test(arguments: [(UInt16(0x10), SIMD3<Float>(1, 1, 0)), (UInt16(0), SIMD3<Float>(1, 0, 0))])
    func pathPositionFollowsTheVelocityFlag(flags: UInt16, expected: SIMD3<Float>) throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiPathInterpolator", NIFBlockFixture.pathInterpolator(
                flags: flags, pathData: 1, percentData: 2
            )),
            .init("NiPosData", NIFBlockFixture.keyGroup([
                (0, [0, 0, 0]), (1, [1, 0, 0]), (2, [1, 3, 0])
            ])),
            .init("NiFloatData", NIFBlockFixture.keyGroup([(0, [0]), (2, [1])]))
        ]))
        let decoded = try NIFCameraPath(interpolatorRef: 0, file: file)
        let path = try #require(decoded)
        let position = try #require(path.position(at: 1))
        #expect(simd_distance(position, expected) < 1e-5)
    }

    @Test func fieldOfViewKeysAreDegrees() throws {
        var interpolator = NIFBlockFixture.floats([-Float.greatestFiniteMagnitude])
        interpolator.appendRef(2)
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("BSFrustumFOVController", NIFBlockFixture.interpolatedController(
                stop: 2, interpolator: 1
            )),
            .init("NiFloatInterpolator", interpolator),
            .init("NiFloatData", NIFBlockFixture.keyGroup([(0, [60]), (2, [90])]))
        ]))
        let decoded = try NIFFieldOfViewTrack(controllerRef: 0, file: file)
        let track = try #require(decoded)
        let radians = try #require(track.horizontalFieldOfView(at: 1))
        #expect(abs(radians - 75 * .pi / 180) < 1e-5)
    }

    @Test func extraDataAndAlphaTestTracks() throws {
        let file = try NIFFile(data: Self.sequenceFile())
        let sequence = try #require(file.sequences().first)
        #expect(sequence.tracks.count == 2)
        let channels = sequence.tracks.map(\.channel)
        guard case let .extraDataFloat(name, keys) = channels[0] else {
            Issue.record("first track is \(channels[0])")
            return
        }
        #expect(name == "hkVis:Star")
        #expect(NIFKeySampler.float(keys, at: 1) == 0)
        guard case let .alphaTestReference(alpha) = channels[1] else {
            Issue.record("second track is \(channels[1])")
            return
        }
        #expect(NIFKeySampler.float(alpha, at: 1) == 128)

        let scene = try NIFEffectScene(file: file)
        let star = try #require(scene.node(named: "Star"))
        let pose = NIFEffectPose(scene: scene, playing: [.init(sequence, seconds: 1)])
        #expect(pose.hidden[star])
    }

    private static let strings = [
        "Root", "Star", "Glow", "NiFloatExtraDataController",
        "BSNiAlphaPropertyTestRefController", "hkVis:Star"
    ]

    /// Blocks: 0 root, 1 star, 2 and 3 the extra data keys, 4 their controller,
    /// 5 and 6 the alpha keys, 7 the sequence.
    private static func sequenceFile() -> Data {
        var extraInterpolator = NIFBlockFixture.floats([-Float.greatestFiniteMagnitude])
        extraInterpolator.appendRef(3)
        var alphaInterpolator = NIFBlockFixture.floats([-Float.greatestFiniteMagnitude])
        alphaInterpolator.appendRef(6)
        var extraController = NIFBlockFixture.interpolatedController(stop: 2, interpolator: 2)
        extraController.append(NIFBlockFixture.uint32(5))
        return NIFFixture.file(blocks: [
            .init(
                "NiNode",
                NIFFixture.niNode(prefix: NIFFixture.avObjectPrefix(nameIndex: 0), children: [1])
            ),
            .init("NiNode", NIFFixture.niNode(prefix: NIFFixture.avObjectPrefix(nameIndex: 1))),
            .init("NiFloatInterpolator", extraInterpolator),
            .init("NiFloatData", NIFBlockFixture.keyGroup([(0, [0]), (2, [0])])),
            .init("NiFloatExtraDataController", extraController),
            .init("NiFloatInterpolator", alphaInterpolator),
            .init("NiFloatData", NIFBlockFixture.keyGroup([(0, [128]), (2, [128])])),
            .init("NiControllerSequence", sequence())
        ], strings: strings)
    }

    private static func sequence() -> Data {
        var out = Data()
        out.appendUInt32(2)
        out.appendUInt32(2)
        out.appendUInt32(1)
        // Interpolator, controller, node name, and controller type of each block.
        let controlled: [[UInt32]] = [[2, 4, 0, 3], [5, .max, 1, 4]]
        for refs in controlled {
            out.appendUInt32(refs[0])
            out.appendUInt32(refs[1])
            out.append(0)
            for string in [refs[2], UInt32.max, refs[3], UInt32.max, UInt32.max] {
                out.appendUInt32(string)
            }
        }
        out.append(NIFBlockFixture.floats([1]))
        out.appendRef(-1) // text keys
        out.appendUInt32(0)
        out.append(NIFBlockFixture.floats([1, 0, 2]))
        out.appendRef(-1)
        out.appendRef(-1)
        out.appendUInt16(0)
        return out
    }
}
