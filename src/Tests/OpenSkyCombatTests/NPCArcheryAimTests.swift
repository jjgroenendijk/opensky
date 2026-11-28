// The NPC archer rules from docs/engine/archery.md, NPC archers: lead, noise, arc and
// spread, and an archer in the combat loop that shoots instead of closing in.

import OpenSkyActorsInterface
@testable import OpenSkyCombat
import OpenSkyCombatFixtures
@testable import OpenSkyCombatInterface
import OpenSkyConditions
@testable import OpenSkyFormatsESM
import OpenSkyGameData
import simd
import Testing

@MainActor
struct NPCArcheryAimTests {
    @Test func aStillTargetIsNotLedAndAMovingOneIs() {
        let origin = SIMD3<Float>(0, 0, 0)
        let point = SIMD3<Float>(1000, 0, 0)
        #expect(NPCArcheryAim.lead(from: origin, to: point, velocity: .zero, speed: 2000) == point)
        let led = NPCArcheryAim.lead(
            from: origin, to: point, velocity: SIMD3(0, 100, 0), speed: 2000
        )
        // About half a second of flight: the aim moves about 50 units sideways.
        #expect(abs(led.y - 50) < 2)
        #expect(NPCArcheryAim.lead(
            from: origin, to: SIMD3(9000, 0, 0), velocity: SIMD3(0, 100, 0), speed: 2000
        ) == SIMD3(9000, 0, 0))
    }

    @Test func noiseStaysInsideItsBox() {
        var random = ConditionRandom(seed: 3)
        for _ in 0 ..< 200 {
            let moved = NPCArcheryAim.noisy(.zero, random: &random)
            #expect(all(abs(moved) .<= SIMD3(repeating: 0.9 * 16)))
        }
        #expect(NPCArcheryAim.noisy(.one, random: &random, variance: 0) == .one)
    }

    @Test func theSpreadNarrowsWithSkillAndStaysInsideTheCone() {
        #expect(abs(NPCArcheryAim.maximumSpread(skill: 40, coneDegrees: 4) - 2.4 * .pi / 180)
            < 1e-6)
        #expect(NPCArcheryAim.maximumSpread(skill: 100, coneDegrees: 4) == 0)
        #expect(NPCArcheryAim.maximumSpread(skill: -50, coneDegrees: 4) == 4 * .pi / 180)
        var random = ConditionRandom(seed: 9)
        let forward = SIMD3<Float>(0.6, 0.8, 0)
        let maximum = NPCArcheryAim.maximumSpread(skill: 0, coneDegrees: 4)
        for _ in 0 ..< 200 {
            let shot = NPCArcheryAim.spread(forward, maximum: maximum, random: &random)
            #expect(acos(min(1, simd_dot(shot, forward))) <= maximum * 1.5 + 1e-4)
            #expect(abs(simd_length(shot) - 1) < 1e-4)
        }
        #expect(NPCArcheryAim.spread(forward, maximum: 0, random: &random) == forward)
    }

    @Test func theArcRisesToMeetTheDrop() {
        let flat = NPCArcheryAim.ballistic(
            from: .zero, to: SIMD3(1000, 0, 0), speed: 2000, gravity: 0
        )
        #expect(flat == SIMD3(1, 0, 0))
        let arc = NPCArcheryAim.ballistic(
            from: .zero, to: SIMD3(1000, 0, 0), speed: 2000, gravity: 700
        )
        #expect(arc.z > 0)
        #expect(abs(simd_length(arc) - 1) < 1e-5)
        let tooFar = NPCArcheryAim.ballistic(
            from: .zero, to: SIMD3(100_000, 0, 0), speed: 500, gravity: 700
        )
        #expect(abs(asin(tooFar.z) - .pi / 4) < 1e-5)
    }

    @Test func aTrackMeasuresOneStepOfMovement() {
        var track = TargetTrack(feet: .zero, step: 0)
        track.note(SIMD3(10, 0, 0), step: 0.1, seconds: 0.1)
        track.note(SIMD3(99, 0, 0), step: 0.1, seconds: 0.1)
        #expect(track.velocity == SIMD3(100, 0, 0))
    }

    @Test func anArcherShootsFromRangeInsteadOfClosingIn() {
        let (runtime, world) = CombatLoopFixture.session(feet: SIMD3(1000, 0, 0))
        world.weapons[CombatLoopFixture.opponent] = MeleeWeaponProfile(
            damage: 8, reach: 1, handType: .bow
        )
        CombatLoopFixture.engage(runtime, world)
        CombatLoopFixture.run(runtime, seconds: CombatLoopFixture.cycleSeconds * 2)

        #expect(!world.arrowShots.isEmpty)
        #expect(world.arrowShots.first?.bow.handType == .bow)
        #expect(world.damage[.player] == nil)
    }

    @Test func aProjectileWithoutAimCorrectionFliesStraightAtTheTarget() {
        let origin = SIMD3<Float>(0, 0, 100)
        let centre = SIMD3<Float>(1000, 0, 100)
        let moving = SIMD3<Float>(0, 300, 0)
        var record = Projectile(
            formID: FormID(0x10), flags: [.disableCombatAimCorrection], gravityFactor: 0.35,
            speed: 3000, range: 0, modelPath: nil
        )
        var random = ConditionRandom(seed: 5)
        let straight = CombatLoopWorldPart.ArcheryShots.launch(
            (origin, centre), velocity: moving,
            profile: ProjectileProfile(record: record), random: &random
        )
        #expect(straight == SIMD3(1, 0, 0))
        record = Projectile(
            formID: FormID(0x10), flags: [], gravityFactor: 0.35, speed: 3000, range: 0,
            modelPath: nil
        )
        let corrected = CombatLoopWorldPart.ArcheryShots.launch(
            (origin, centre), velocity: moving,
            profile: ProjectileProfile(record: record), random: &random
        )
        #expect(corrected.y > 0.05)
        #expect(corrected.z > 0)
    }

    @Test func aLobberAimsForFullWorldGravity() {
        var profile = ProjectileProfile(
            speed: 1000, gravityFactor: 0.2, range: 0, collisionRadius: 1
        )
        #expect(profile.aimGravityFactor == 0.2)
        profile.kind = .lobber
        #expect(profile.aimGravityFactor == 1)
    }

    /// A spell area of 10 feet is 220 units, past `fCombatAimProjectileGroundMinRadius`.
    @Test func aLargeBlastIsAimedAtTheFeet() {
        var settings = ArcherySettings.resolve(store: GameSettingStore(plugins: []))
        #expect(settings.groundAimMinimumRadius == 128)
        #expect(settings.aimsAtFeet(explosionRadius: 0, spellArea: 10))
        #expect(settings.aimsAtFeet(explosionRadius: 200, spellArea: 0))
        #expect(!settings.aimsAtFeet(explosionRadius: 128, spellArea: 5))
        #expect(!settings.aimsAtFeet(explosionRadius: .nan, spellArea: 0))
        settings.groundAimMinimumRadius = 300
        #expect(!settings.aimsAtFeet(explosionRadius: 200, spellArea: 10))
    }
}
