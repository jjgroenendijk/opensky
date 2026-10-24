// The pure rules behind the actor-state graph inputs: which `iState` the player is
// in, and every input value for one step. The app fills `ActorStateGraphInputs` from
// combat, magic, and the camera; the locomotion bridge writes the result.

import Foundation
import OpenSkyBehavior
import OpenSkyPhysics
import simd

/// What the other game systems report about the player for one step.
nonisolated public struct ActorStateGraphInputs: Equatable, Sendable {
    public var weaponDrawn = false
    public var isAttacking = false
    public var isPowerAttacking = false
    public var isBlocking = false
    public var isBowDrawn = false
    /// The `iRightHandType` encoding (docs/engine/combat-graph-names.md).
    public var rightHandType: Int32 = 0
    public var leftHandType: Int32 = 0
    /// The race has the `IsBeastRace` keyword.
    public var isBeastRace = false
    /// The player swims, so a get-up uses the swimming pose matcher.
    public var swimming = false
    public var castingLeft = false
    public var castingRight = false
    /// The player holds the shout key and may shout.
    public var wantsVoice = false
    /// The Head tracking setting.
    public var headTracking = true
    public var cameraPosition = SIMD3<Float>()
    /// A point along the view, world space.
    public var lookTarget = SIMD3<Float>()
    /// Radians, positive looks up.
    public var cameraPitch: Float = 0
    /// The player sits on a mount, and whether the mount sprints. Nil on foot.
    public var riding: RiderGait?

    public init() {}

    /// How far ahead of the camera the look target sits. Ours; no setting names it.
    public static let lookDistance: Float = 1024

    /// Places the camera and the look target from one camera pose.
    public mutating func setCamera(position: SIMD3<Float>, forward: SIMD3<Float>, pitch: Float) {
        cameraPosition = position
        lookTarget = position + forward * Self.lookDistance
        cameraPitch = pitch
    }
}

/// How the mount under the player moves, as `iState` sees it.
nonisolated public enum RiderGait: Equatable, Sendable {
    case riding
    case sprinting
}

nonisolated public enum ActorStateGraphCore: Sendable {
    /// The state `iState` reports. The order is ours: riding wins over everything, an
    /// attack over a guard, a guard over a drawn bow, and a cast over movement.
    /// Bleedout, drunk, quick shot, and shield charge have no OpenSky system, so no
    /// step picks them.
    public static func state(
        for inputs: ActorStateGraphInputs, gait: LocomotionGait
    ) -> ActorGraphState {
        if let riding = inputs.riding {
            return riding == .sprinting ? .horseSprint : .npcHorse
        }
        let twoHanded = inputs.rightHandType == 5 || inputs.rightHandType == 6
        if inputs.isAttacking {
            if inputs.isPowerAttacking {
                return .npcPowerAttacking
            }
            return twoHanded ? .npcAttacking2H : .npcAttacking
        }
        if inputs.isBlocking {
            return .npcBlocking
        }
        if inputs.isBowDrawn {
            return .npcBowDrawn
        }
        if inputs.castingLeft || inputs.castingRight {
            return .npcMagicCasting
        }
        switch gait {
        case .sprint: return .npcSprinting
        case .sneak: return .npcSneaking
        default: break
        }
        guard inputs.weaponDrawn else { return .npcDefault }
        return drawnState(rightHandType: inputs.rightHandType)
    }

    private static func drawnState(rightHandType: Int32) -> ActorGraphState {
        switch rightHandType {
        case 1 ... 4: .npc1HM
        case 5, 6: .npc2HM
        case 7, 12: .npcBow
        case 8, 9: .npcMagic
        default: .npcDefault
        }
    }

    /// Every input for one step, in `ActorStateGraphNames.inputs` order. `iState` is
    /// left out when the graph declares no constant for the state.
    public static func writes(
        _ inputs: ActorStateGraphInputs,
        sprintAllowed: Bool,
        wantsBlock: Bool,
        stateValue: Int32?
    ) -> [(name: String, value: BehaviorVariableValue)] {
        let casting = inputs.castingLeft || inputs.castingRight
        func drawn(_ handType: Int32) -> Int32 {
            inputs.weaponDrawn ? handType : 0
        }
        var writes: [(name: String, value: BehaviorVariableValue)] = [
            (ActorStateGraphNames.headTracking, .bool(inputs.headTracking)),
            (ActorStateGraphNames.targetLocation, .quad(SIMD4(inputs.lookTarget, 0))),
            (ActorStateGraphNames.cameraFromX, .real(inputs.cameraPosition.x)),
            (ActorStateGraphNames.cameraFromY, .real(inputs.cameraPosition.y)),
            (ActorStateGraphNames.cameraFromZ, .real(inputs.cameraPosition.z)),
            (ActorStateGraphNames.pitch, .real(inputs.cameraPitch)),
            (ActorStateGraphNames.sprintOK, .bool(sprintAllowed)),
            (ActorStateGraphNames.wantBlock, .int(wantsBlock ? 1 : 0)),
            (ActorStateGraphNames.wantCastLeft, .bool(inputs.castingLeft)),
            (ActorStateGraphNames.wantCastRight, .bool(inputs.castingRight)),
            (ActorStateGraphNames.wantCastVoice, .bool(inputs.wantsVoice)),
            (ActorStateGraphNames.inCastState, .real(casting ? 1 : 0)),
            (
                ActorStateGraphNames.combatStance,
                .int(MountGraphNames.combatStanceValue(inputs.weaponDrawn))
            ),
            (ActorStateGraphNames.rightHandEquipped, .int(drawn(inputs.rightHandType))),
            (ActorStateGraphNames.leftHandEquipped, .int(drawn(inputs.leftHandType))),
            (ActorStateGraphNames.isBeastRace, .bool(inputs.isBeastRace)),
            (ActorStateGraphNames.getUpType, .int(getUpType(swimming: inputs.swimming)))
        ]
        if let stateValue {
            writes.append((ActorStateGraphNames.state, .int(stateValue)))
        }
        return writes
    }

    /// The player is alive, so a get-up never uses the reanimate pose matcher.
    public static func getUpType(swimming: Bool) -> Int32 {
        swimming ? 2 : 1
    }

    /// The readout name of an `iState` value: the constant that holds it, or the
    /// number alone when no constant does.
    public static func stateName(of value: Int32, constants: [ActorGraphState: Int32]) -> String {
        let named = ActorGraphState.allCases.first { constants[$0] == value }
        return named.map { "\(value) (\($0.displayName))" } ?? String(value)
    }
}
