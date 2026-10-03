// The facts the camera-path conditions read for one kill: the attack kind from
// the weapon, and which sides of the attacker have room for a camera. See
// docs/formats/camera-records.md#condition-functions.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import simd

nonisolated public enum CameraShotFacts {
    /// How far each side is probed. Paths ask for at most 256 units of room.
    public static let probeDistance: Float = 512
    /// Room a side needs before the target counts as visible from it. OpenSky's choice.
    public static let visibleClearance: Float = 150
    /// xEdit's VATS action values.
    public static let meleeAction: UInt32 = 1
    public static let rangedAction: UInt32 = 4

    /// `room` gets a world-space offset from the attacker's chest and returns
    /// how far a camera could move along it. `yaw` follows `FreeFlyCamera`.
    public static func resolution(
        weapon: Weapon?,
        targetBase: FormID?,
        targetDistance: Float?,
        yaw: Float,
        room: (SIMD3<Float>) -> Float
    ) -> CameraConditionResolution {
        var facts = CameraConditionResolution()
        facts.isAvailable = true
        facts.weapon = weapon?.formID
        facts.weaponType = weapon?.animationType.map { UInt32($0.rawValue) }
        facts.action = isRanged(weapon) ? rangedAction : meleeAction
        facts.targetBase = targetBase
        facts.targetDistance = targetDistance
        if isRanged(weapon) {
            facts.projectileType = 6
        }
        for side in CameraConditionResolution.Side.allCases {
            facts.freeDistance[side] = min(
                room(direction(of: side, yaw: yaw) * probeDistance),
                probeDistance
            )
        }
        facts
            .targetVisibleSides = Set([.right, .left]
                .filter { (facts.freeDistance[$0] ?? 0) >= visibleClearance })
        return facts
    }

    public static func direction(
        of side: CameraConditionResolution.Side,
        yaw: Float
    ) -> SIMD3<Float> {
        let forward = SIMD3<Float>(cosf(yaw), sinf(yaw), 0)
        let right = SIMD3<Float>(sinf(yaw), -cosf(yaw), 0)
        return switch side {
        case .front: forward
        case .back: -forward
        case .right: right
        case .left: -right
        }
    }

    private static func isRanged(_ weapon: Weapon?) -> Bool {
        weapon?.animationType == .bow || weapon?.animationType == .crossbow
    }
}
