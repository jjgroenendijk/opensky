// A held turn on a ridden horse starts slow, ramps to the maximum, and resets on release.

import OpenSkyPlayer
import OpenSkyWorldInterface
import Testing

struct MountTurnRampTests {
    private let settings: MountSettings = {
        var settings = MountSettings.vanilla
        settings.turnDegreesPerSecond = 45
        settings.turnRampUpDegreesPerSecond = 90
        return settings
    }()

    private func degrees(_ radians: Float) -> Float {
        radians * 180 / .pi
    }

    @Test func aHeldTurnRampsUpToTheMaximum() {
        var ramp = MountTurnRamp()

        let first = ramp.advance(wantedTurn: 1, deltaTime: 0.1, settings: settings)
        #expect(abs(degrees(first) - 9) < 1e-3)
        for _ in 0 ..< 3 {
            _ = ramp.advance(wantedTurn: 1, deltaTime: 0.1, settings: settings)
        }
        #expect(abs(degrees(ramp.rate) - 36) < 1e-3)
        _ = ramp.advance(wantedTurn: -1, deltaTime: 0.1, settings: settings)
        _ = ramp.advance(wantedTurn: -1, deltaTime: 0.1, settings: settings)
        #expect(abs(degrees(ramp.rate) - 45) < 1e-3)
    }

    @Test func releasingOrFacingTheGoalResetsTheRate() {
        var ramp = MountTurnRamp()
        _ = ramp.advance(wantedTurn: 1, deltaTime: 0.3, settings: settings)

        #expect(ramp.advance(wantedTurn: nil, deltaTime: 0.1, settings: settings) == 0)
        _ = ramp.advance(wantedTurn: 1, deltaTime: 0.3, settings: settings)
        #expect(ramp.advance(wantedTurn: 0.0001, deltaTime: 0.1, settings: settings) == 0)
    }

    @Test func aPausedFrameKeepsTheRate() {
        var ramp = MountTurnRamp()
        _ = ramp.advance(wantedTurn: 1, deltaTime: 0.2, settings: settings)

        let paused = ramp.advance(wantedTurn: 1, deltaTime: 0, settings: settings)
        #expect(abs(degrees(paused) - 18) < 1e-3)
        let pausedRelease = ramp.advance(wantedTurn: nil, deltaTime: 0, settings: settings)
        #expect(abs(degrees(pausedRelease) - 18) < 1e-3)
    }

    @Test func wantedTurnIsTheAngleToThePushedDirection() throws {
        let left = try #require(
            MountRules.wantedTurn(heading: 0, forward: 0, right: -1, cameraYaw: 0)
        )
        #expect(abs(left - .pi / 2) < 1e-5)
        #expect(MountRules.wantedTurn(heading: 0, forward: 0, right: 0, cameraYaw: 0) == nil)
    }
}
