// The heartbeat and pulse the game gives while the player's health is low.

@testable import OpenSkyEffects
import OpenSkyWorldInterface
import Testing

struct PlayerHealthCuesTests {
    @Test
    func heartbeatBandsIncludeTheirTop() {
        #expect(PlayerHealthCues.heartbeat(for: 0.5) == nil)
        #expect(PlayerHealthCues.heartbeat(for: 0.2) == .slow)
        #expect(PlayerHealthCues.heartbeat(for: 0.15) == .slow)
        #expect(PlayerHealthCues.heartbeat(for: 0.1) == .fast)
        #expect(PlayerHealthCues.heartbeat(for: 0) == nil)
    }

    @Test
    func pulseStrengthRunsFromWeakToStrong() {
        #expect(abs(PlayerHealthCues.pulseStrength(share: 0.2) - 0.8) < 1e-5)
        #expect(abs(PlayerHealthCues.pulseStrength(share: 0.15) - 1.15) < 1e-5)
        #expect(abs(PlayerHealthCues.pulseStrength(share: 0.1) - 1.5) < 1e-5)
        #expect(abs(PlayerHealthCues.pulseStrength(share: 0) - 1.5) < 1e-5)
    }

    @Test
    func heartbeatChangesOnlyWithHealth() {
        var cues = PlayerHealthCues()
        #expect(cues.healthChanged(share: 1, heartbeatPlaying: false) == nil)
        #expect(cues.healthChanged(share: 0.18, heartbeatPlaying: false) == .start(.slow))
        #expect(cues.healthChanged(share: 0.18, heartbeatPlaying: false) == nil)
        #expect(cues.healthChanged(share: 0.17, heartbeatPlaying: true) == nil)
        #expect(cues.healthChanged(share: 0.16, heartbeatPlaying: false) == .start(.slow))
        #expect(cues.healthChanged(share: 0.05, heartbeatPlaying: true) == .start(.fast))
        #expect(cues.healthChanged(share: 0, heartbeatPlaying: true) == .fadeOut)
        #expect(cues.healthChanged(share: 0.9, heartbeatPlaying: false) == nil)
    }

    @Test
    func pulseFiresAtOnceThenEveryInterval() {
        var cues = PlayerHealthCues()
        _ = cues.healthChanged(share: 0.15, heartbeatPlaying: false)
        #expect(cues.advance(0.016) != nil)
        #expect(cues.advance(1.9) == nil)
        #expect(cues.advance(0.2) != nil)
        #expect(cues.pulseCount == 2)
        #expect(cues.lastPulseStrength == PlayerHealthCues.pulseStrength(share: 0.15))
        _ = cues.healthChanged(share: 0.5, heartbeatPlaying: true)
        #expect(cues.advance(5) == nil)
    }

    @Test
    func switchedOffPulseNeverFires() {
        var cues = PlayerHealthCues()
        cues.pulseEnabled = false
        _ = cues.healthChanged(share: 0.1, heartbeatPlaying: false)
        #expect(cues.advance(1) == nil)
    }

    @Test
    func resetForgetsHealthButKeepsTheSwitch() {
        var cues = PlayerHealthCues()
        cues.pulseEnabled = false
        _ = cues.healthChanged(share: 0.15, heartbeatPlaying: false)
        cues.reset()
        #expect(cues.heartbeat == nil)
        #expect(cues.pulseEnabled == false)
        #expect(cues.healthChanged(share: 0.15, heartbeatPlaying: false) == .start(.slow))
    }

    @Test
    func noMaximumCountsAsFullHealth() {
        #expect(PlayerHealthCues.share(current: 5, maximum: 0) == 1)
        #expect(PlayerHealthCues.share(current: 25, maximum: 100) == 0.25)
    }
}
