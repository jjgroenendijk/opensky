// A loading screen path plays its `CameraPath` sequence: the node's keys set the
// camera, the first pose is a millisecond in, and the file's cycle loops or holds.

import Foundation
@testable import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
@testable import OpenSkyMenuAdapters
import simd
import Testing

struct LoadingCameraPathTests {
    /// `NiTransformData` with no rotation keys and two linear translation keys.
    private static func keys() throws -> NIFTransformData {
        var data = Data()
        func put(_ value: UInt32) {
            data.append(contentsOf: (0 ..< 4).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) })
        }
        func put(_ value: Float) {
            put(value.bitPattern)
        }
        put(UInt32(0)) // rotation keys
        put(UInt32(2)) // translation keys
        put(UInt32(1)) // linear
        for (time, point) in [(Float(0), SIMD3<Float>(0, -25, 35)), (30, .zero)] {
            put(time)
            put(point.x)
            put(point.y)
            put(point.z)
        }
        put(UInt32(0)) // scale keys
        return try NIFTransformData(data: data)
    }

    private static func path(_ cycle: ControllerCycle) throws -> LoadingCameraPath {
        let channel = try NIFTransformChannel(
            translation: nil, rotation: nil, scale: nil, keys: keys()
        )
        let sequence = NIFSequence(
            name: "CameraPath",
            timing: ControllerTiming(
                cycle: cycle, frequency: 1, phase: 0, startTime: 0, stopTime: 30
            ),
            textKeys: [],
            tracks: [NIFSequenceTrack(
                target: .node("CameraPathNode"),
                channel: .transform(channel)
            )]
        )
        return LoadingCameraPath(sequence: sequence, channel: channel, rest: [1, 2, 3])
    }

    @Test func theNodeFollowsItsKeys() throws {
        let path = try Self.path(.clamp)
        #expect(simd_length(path.nodePosition(after: 15) - [0, -12.5, 17.5]) < 0.01)
        #expect(path.nodePosition(after: 0).y > -25, "the first pose is a millisecond in")
        #expect(path.nodePosition(after: 45) == .zero, "a clamp holds its end")
    }

    @Test func aLoopStartsAgain() throws {
        let path = try Self.path(.loop)
        #expect(simd_length(path.nodePosition(after: 45) - [0, -12.5, 17.5]) < 0.01)
    }

    @Test func aPathWithoutTheSequenceStaysAtRest() {
        let path = LoadingCameraPath(sequence: nil, channel: nil, rest: [1, 2, 3])
        #expect(path.nodePosition(after: 10) == [1, 2, 3])
    }

    @Test func aFileWithoutTheSequenceRestsWhereItsCameraStands() throws {
        let file = try NIFFile(data: NIFFixture.cameraFile(translations: [(0, [4, 5, 6])]))
        let path = try LoadingCameraPath(file: file)
        #expect(path.sequence == nil)
        #expect(path.nodePosition(after: 3) == path.rest)
    }
}
