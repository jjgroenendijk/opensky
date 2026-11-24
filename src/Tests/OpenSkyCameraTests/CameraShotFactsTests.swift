// The facts camera-path conditions read: sides come from the attacker's
// heading, an unarmed attack is a melee action, and a cast spell is a magic one.

@testable import OpenSkyCamera
import OpenSkyConditions
import OpenSkyFormatsESM
import simd
import Testing

struct CameraShotFactsTests {
    @Test func sidesFollowTheHeading() {
        let east = CameraShotFacts.direction(of: .front, yaw: 0)
        #expect(simd_distance(east, [1, 0, 0]) < 1e-5)
        #expect(simd_distance(CameraShotFacts.direction(of: .right, yaw: 0), [0, -1, 0]) < 1e-5)
        let north = CameraShotFacts.direction(of: .front, yaw: .pi / 2)
        #expect(simd_distance(north, [0, 1, 0]) < 1e-5)
    }

    @Test func roomIsMeasuredPerSideAndAnUnarmedKillIsMelee() {
        let facts = CameraShotFacts.resolution(
            weapon: nil, target: (FormID(0x1234), 900), yaw: 0
        ) { offset in
            offset.y < -1 ? 1000 : 40
        }
        #expect(facts.isAvailable)
        #expect(facts.freeDistance[.right] == CameraShotFacts.probeDistance)
        #expect(facts.freeDistance[.left] == 40)
        #expect(facts.targetDistance == 900)
        #expect(facts.targetVisibleSides == [CameraConditionResolution.Side.right])
        #expect(facts.action == CameraShotFacts.meleeAction)
        #expect(facts.weaponType == nil)
        #expect(facts.targetBase == FormID(0x1234))
    }

    @Test func aSpellShotIsAMagicActionWithItsProjectileType() {
        var facts = CameraShotFacts.resolution(weapon: nil, target: (nil, 130), yaw: 0) { _ in 0 }
        CameraShotFacts.noteSpell(
            &facts, projectile: .beam, delivery: .aimed, castingType: .concentration
        )
        #expect(facts.action == CameraShotFacts.magicAction)
        #expect(facts.projectileType == 2)
        #expect(facts.delivery == 2)
        #expect(facts.castingType == 2)
        CameraShotFacts.noteSpell(
            &facts, projectile: nil, delivery: .selfTarget, castingType: .fireAndForget
        )
        #expect(facts.projectileType == nil)
        #expect(facts.delivery == 0)
        #expect(facts.castingType == 1)
    }
}
