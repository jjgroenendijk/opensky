// When a kill cam plays, which actor an arrow will kill, and the shake curve.

@testable import OpenSkyConditions
import OpenSkyFormatsESM
@testable import OpenSkyWorld
import simd
import Testing

struct KillCamTriggerTests {
    private static let near = ReferenceKey.plugin(name: "Base.esm", objectID: 0x10)
    private static let far = ReferenceKey.plugin(name: "Base.esm", objectID: 0x11)

    private static func candidate(
        _ key: ReferenceKey,
        x: Float,
        health: Float
    ) -> KillCamCandidate {
        KillCamCandidate(key: key, position: [x, 0, 0], radius: 30, height: 128, health: health)
    }

    @Test func onlyTheLastEnemyPlaysByDefault() {
        var random = ConditionRandom(seed: 1)
        let settings = KillCamSettings()
        #expect(KillCamTrigger.shouldPlay(
            settings: settings,
            remainingHostiles: 0,
            random: &random
        ))
        #expect(!KillCamTrigger.shouldPlay(
            settings: settings,
            remainingHostiles: 2,
            random: &random
        ))
        var everyKill = settings
        everyKill.lastEnemyOnly = false
        #expect(KillCamTrigger.shouldPlay(
            settings: everyKill,
            remainingHostiles: 2,
            random: &random
        ))
        var off = settings
        off.enabled = false
        #expect(!KillCamTrigger.shouldPlay(settings: off, remainingHostiles: 0, random: &random))
        var never = settings
        never.baseOdds = 0
        #expect(!KillCamTrigger.shouldPlay(settings: never, remainingHostiles: 0, random: &random))
    }

    @Test func arrowPicksTheNearestActorItKills() {
        let candidates = [
            Self.candidate(Self.far, x: 900, health: 10),
            Self.candidate(Self.near, x: 400, health: 10)
        ]
        let kill = KillCamTrigger.arrowKill(
            origin: [0, 0, 100], direction: [1, 0, 0], range: 2000, damage: 20,
            candidates: candidates
        )
        #expect(kill?.key == Self.near)
    }

    @Test func arrowIgnoresActorsItWouldNotKillOrMisses() {
        let tough = [Self.candidate(Self.near, x: 400, health: 50)]
        #expect(KillCamTrigger.arrowKill(
            origin: [0, 0, 100], direction: [1, 0, 0], range: 2000, damage: 20, candidates: tough
        ) == nil)
        let aside = [KillCamCandidate(
            key: Self.near,
            position: [400, 200, 0],
            radius: 30,
            height: 128,
            health: 5
        )]
        #expect(KillCamTrigger.arrowKill(
            origin: [0, 0, 100], direction: [1, 0, 0], range: 2000, damage: 20, candidates: aside
        ) == nil)
        let beyond = [Self.candidate(Self.near, x: 4000, health: 5)]
        #expect(KillCamTrigger.arrowKill(
            origin: [0, 0, 100], direction: [1, 0, 0], range: 2000, damage: 20, candidates: beyond
        ) == nil)
    }

    @Test func shakeFadesOutAndFallsOffWithDistance() {
        let shake = CameraShake(strength: 2, duration: 0, startedAt: 10)
        #expect(shake.strength == 1)
        #expect(shake.duration == CameraShake.defaultDuration)
        #expect(shake.offset(at: 9) == .zero)
        #expect(simd_length(shake.offset(at: 10.05)) > 0)
        #expect(shake.offset(at: 11) == .zero)
        #expect(shake.isFinished(at: 11))
        #expect(CameraShake.strength(1, atDistance: nil) == 1)
        #expect(CameraShake.strength(1, atDistance: 1024) == 0.5)
        #expect(CameraShake.strength(1, atDistance: 4096) == 0)
    }
}
