// The state a new session's audio, sky, rig, and motion parts start with.

@testable import OpenSkyWorld
import simd
import Testing

@MainActor
struct SessionPartsTests {
    @Test func aNewSessionHasNoAudioWork() {
        let audio = SessionAudio()
        #expect(audio.worldAudio == nil)
        #expect(audio.lastAudioUpdateMS == 0)
    }

    @Test func aNewSessionRunsWeather() {
        let sky = SessionSky()
        #expect(sky.weatherEnabled)
        #expect(sky.currentResolvedWeather == nil)
    }

    @Test func aNewSessionHasNoPlayerBody() {
        let rigs = SessionRigs()
        #expect(rigs.playerBody == nil)
        #expect(rigs.firstPersonArmsEnabled)
    }

    @Test func aNewSessionPlayerCanMove() {
        let motion = SessionMotion()
        #expect(!motion.isPlayerParalysed)
        #expect(motion.playerWalkPath.isEmpty)
    }

    @Test func aSeatedPlayerHeadMovesWithTheSeat() {
        let motion = SessionMotion()
        #expect(motion.seatedHeadInWorld == nil)
        var seat = matrix_identity_float4x4
        seat.columns.3 = SIMD4(100, 0, 50, 1)
        motion.playerSeat = seat
        motion.seatedHead = SIMD3(0, 10, 90)
        #expect(motion.seatedHeadInWorld == SIMD3(100, 10, 140))
    }
}
