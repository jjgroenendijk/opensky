// The facts camera-path conditions read: sides come from the attacker's
// heading, and an unarmed attack is a melee action.

import OpenSkyConditions
import OpenSkyFormatsESM
@testable import OpenSkyWorld
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
            weapon: nil, targetBase: FormID(0x1234), targetDistance: 900, yaw: 0
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
}
