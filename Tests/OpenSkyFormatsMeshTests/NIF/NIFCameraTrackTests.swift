// The camera track decode: the NiCamera's controller chain down to its keys,
// sampling between keys, and broken links that must not crash.

import FormatsCoreTesting
import FormatsMeshTesting
import Foundation
@testable import OpenSkyFormatsMesh
import simd
import TagsTesting
import Testing

@Suite(.tags(.parser))
struct NIFCameraTrackTests {
    @Test func followsTheControllerChainToItsKeys() throws {
        let file = try NIFFile(data: NIFFixture.cameraFile(
            translations: [(0, [0, 0, 0]), (2, [100, 0, 50])],
            rotations: [
                (0, simd_quatf(angle: 0, axis: [0, 0, 1])),
                (2, simd_quatf(angle: .pi / 2, axis: [0, 0, 1]))
            ]
        ))
        let track = try NIFCameraTrack(file: file)
        #expect(track.restTranslation == [1, 2, 3])
        #expect(track.startTime == 0)
        #expect(track.stopTime == 2)
        #expect(track.keys?.rotationType == .linear)
        #expect(track.keys?.translations.count == 2)
        #expect(track.translation(at: 1) == [50, 0, 25])
        #expect(track.translation(at: 5) == [100, 0, 50])
        let half = track.rotation(at: 1)
        #expect(abs(half.angle - .pi / 4) < 0.001)
        #expect(abs(track.horizontalFieldOfView - 2 * atan(1)) < 0.001)
    }

    @Test func skipsAFieldOfViewControllerAheadOfTheTransformController() throws {
        let file = try NIFFile(data: NIFFixture.cameraFile(
            translations: [(0, [0, 0, 0]), (2, [100, 0, 50])], fieldOfViewControllerFirst: true
        ))
        let track = try NIFCameraTrack(file: file)
        #expect(track.stopTime == 2)
        #expect(track.translation(at: 1) == [50, 0, 25])
    }

    @Test func anAnimatedRootCarriesTheCameraBelowIt() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("BSFadeNode", NIFFixture.niNode(
                prefix: NIFFixture.avObjectPrefix(controllerRef: 1, translation: [5, 0, 0]),
                children: [4]
            )),
            .init(
                "NiTransformController",
                NIFFixture.transformController(interpolator: 2, start: 0, stop: 2)
            ),
            .init("NiTransformInterpolator", NIFFixture.transformInterpolator(data: 3)),
            .init("NiTransformData", NIFFixture.transformData(
                rotations: [(0, simd_quatf(angle: .pi / 2, axis: [0, 0, 1]))],
                translations: [(0, [0, 0, 0]), (2, [100, 0, 0])]
            )),
            .init(
                "NiCamera",
                NIFFixture.niCamera(prefix: NIFFixture.avObjectPrefix(translation: [10, 0, 0]))
            )
        ]))
        let track = try NIFCameraTrack(file: file)
        #expect(track.stopTime == 2)
        #expect(track.offsetTranslation == [10, 0, 0])
        // The root turns a quarter around Z, so the camera's +X offset points along +Y.
        #expect(simd_distance(track.translation(at: 2), [100, 10, 0]) < 1e-4)
    }

    @Test func cameraWithoutAControllerRestsInPlace() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init(
                "NiCamera",
                NIFFixture.niCamera(prefix: NIFFixture.avObjectPrefix(translation: [4, 5, 6]))
            )
        ]))
        let track = try NIFCameraTrack(file: file)
        #expect(track.keys == nil)
        #expect(track.translation(at: 1) == [4, 5, 6])
    }

    @Test func fileWithoutACameraThrows() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [.init(
            "NiNode",
            NIFFixture.niNode()
        )]))
        #expect(throws: NIFError.self) { try NIFCameraTrack(file: file) }
    }

    @Test func keyCountPastTheBlockThrows() {
        var data = Data()
        data.appendUInt32(0x7FFF_FFFF)
        data.appendUInt32(1)
        #expect(throws: NIFError.self) { try NIFTransformData(data: data) }
    }

    @Test func unknownKeyTypeThrows() {
        var data = Data()
        data.appendUInt32(1)
        data.appendUInt32(9)
        #expect(throws: NIFError.self) { try NIFTransformData(data: data) }
    }
}
