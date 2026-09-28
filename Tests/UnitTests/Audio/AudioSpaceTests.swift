// World-to-listener conversion coverage (docs/engine/audio.md): the Z-up
// native-unit world maps into AVAudioEnvironmentNode's Y-up meter space as
// (x, y, z) -> (x, z, -y) with positions scaled by metersPerUnit.

@testable import opensky
import simd
import Testing

struct AudioSpaceTests {
    private func expectClose(
        _ actual: SIMD3<Float>, _ expected: SIMD3<Float>,
        tolerance: Float = 1e-5
    ) {
        #expect(
            simd_distance(actual, expected) < tolerance,
            "expected \(expected), got \(actual)"
        )
    }

    @Test
    func positionMapsAxesAndScalesToMeters() {
        // One meter east (+X stays +X).
        expectClose(
            AudioSpace.listenerPosition(fromWorld: SIMD3(1 / 0.0142875, 0, 0)),
            SIMD3(1, 0, 0)
        )
        // North (+Y) becomes -Z: ahead of a Y-up listener facing -Z.
        expectClose(
            AudioSpace.listenerPosition(fromWorld: SIMD3(0, 1 / 0.0142875, 0)),
            SIMD3(0, 0, -1)
        )
        // Up (+Z) becomes +Y.
        expectClose(
            AudioSpace.listenerPosition(fromWorld: SIMD3(0, 0, 1 / 0.0142875)),
            SIMD3(0, 1, 0)
        )
        expectClose(AudioSpace.listenerPosition(fromWorld: .zero), .zero)
    }

    @Test
    func directionsMapAxesWithoutScaling() {
        expectClose(
            AudioSpace.listenerDirection(fromWorld: SIMD3(0, 1, 0)), SIMD3(0, 0, -1)
        )
        expectClose(
            AudioSpace.listenerDirection(fromWorld: SIMD3(0, 0, 1)), SIMD3(0, 1, 0)
        )
        expectClose(
            AudioSpace.listenerDirection(fromWorld: SIMD3(1, 0, 0)), SIMD3(1, 0, 0)
        )
    }

    @Test
    func forwardFollowsFreeFlyYawPitchConvention() {
        // Yaw 0, level: facing +X east.
        expectClose(AudioSpace.worldForward(yaw: 0, pitch: 0), SIMD3(1, 0, 0))
        // Yaw +90 degrees: facing +Y north.
        expectClose(AudioSpace.worldForward(yaw: .pi / 2, pitch: 0), SIMD3(0, 1, 0))
        // Pitch +90 degrees: facing straight up.
        expectClose(AudioSpace.worldForward(yaw: 0, pitch: .pi / 2), SIMD3(0, 0, 1))
    }

    @Test
    func upStaysOrthogonalToForward() {
        for (yaw, pitch) in [(Float(0), Float(0)), (0.7, 0.3), (-2.1, -0.9), (3.0, 1.2)] {
            let forward = AudioSpace.worldForward(yaw: yaw, pitch: pitch)
            let upward = AudioSpace.worldUp(yaw: yaw, pitch: pitch)
            #expect(abs(simd_dot(forward, upward)) < 1e-5)
            #expect(abs(simd_length(upward) - 1) < 1e-5)
        }
        // Level pose: up is world +Z.
        expectClose(AudioSpace.worldUp(yaw: 0.4, pitch: 0), SIMD3(0, 0, 1))
    }

    @Test
    func distanceIsMeters() {
        let cellSpan: Float = 4096
        let meters = AudioSpace.distanceMeters(
            fromWorld: .zero, toWorld: SIMD3(cellSpan, 0, 0)
        )
        // One exterior cell is ~58.5 m (docs/decisions/coordinates.md).
        #expect(abs(meters - cellSpan * 0.0142875) < 1e-3)
    }
}
