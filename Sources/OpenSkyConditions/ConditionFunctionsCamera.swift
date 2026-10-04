// The VATS camera condition functions that CPTH camera paths test: 407
// `GetVATSValue`, 515 to 518 `GetVATS...AreaFree`, and 522 and 523
// `GetVATS...TargetVisible`, from xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas.
// They read the shot being chosen, not a reference. See docs/formats/camera-records.md.

import Foundation
import OpenSkyFormatsESM

/// The facts of one cinematic shot request: the attack, and the free space
/// around the attacker. The kill-cam coordinator fills it per selection.
nonisolated public struct CameraConditionResolution: Equatable, Sendable {
    nonisolated public enum Side: Int, CaseIterable, Sendable {
        case right, left, back, front
    }

    /// xEdit's VATS Action enum: 1 one-hand melee, 4 ranged, 11 player death.
    public var action: UInt32?
    public var weapon: FormID?
    /// xEdit's weapon animation type: 7 bow, 9 crossbow.
    public var weaponType: UInt32?
    /// The target's base form.
    public var targetBase: FormID?
    /// xEdit's projectile type: 0 missile, 2 beam, 6 arrow.
    public var projectileType: UInt32?
    /// Magic delivery and casting type, as the MGEF stores them.
    public var delivery: UInt32?
    public var castingType: UInt32?
    /// Free room beside the attacker in game units; paths ask for `>= 150`.
    public var freeDistance: [Side: Float] = [:]
    /// Units from attacker to target; paths ask for `>= 768`.
    public var targetDistance: Float?
    /// The sides from which the target can be seen past the attacker.
    public var targetVisibleSides: Set<Side> = []
    /// False in a context with no shot request, so every function fails honestly.
    public var isAvailable = false

    public static let empty = CameraConditionResolution()

    public init() {}
}

nonisolated extension CameraConditionResolution: ConditionResolution {}

nonisolated extension ConditionContext {
    public var camera: CameraConditionResolution {
        get { self[resolution: CameraConditionResolution.self] }
        set { self[resolution: CameraConditionResolution.self] = newValue }
    }
}

nonisolated extension ConditionFunctions {
    /// `GetVATSValue` members by xEdit's parameter-1 index.
    private enum VATSValue: UInt32 {
        case weapon = 0
        case target = 2
        case targetDistance = 4
        case action = 6
        case weaponType = 15
        case projectileType = 18
        case delivery = 19
        case castingType = 20
    }

    public static func installCamera(_ registry: inout ConditionFunctionRegistry) {
        registry.register(ConditionFunction(
            index: 407, name: "GetVATSValue", parameter1: .integer, parameter2: .integer
        ) { call in
            let camera = call.context.camera
            guard camera.isAvailable else { return .failure(.unavailableData(.camera)) }
            guard let selector = VATSValue(rawValue: call.condition.parameter1.rawValue) else {
                return .failure(.unresolvedParameter(407))
            }
            if selector == .targetDistance {
                return .success(camera.targetDistance ?? 0)
            }
            return .success(isTrue(vatsValue(selector, camera) == call.condition.parameter2
                    .rawValue))
        })
        for function in SideFunction.areaFree {
            register(function, &registry) { .success($0.freeDistance[$1] ?? 0) }
        }
        for function in SideFunction.targetVisible {
            register(function, &registry) { .success(isTrue($0.targetVisibleSides.contains($1))) }
        }
    }

    private static func vatsValue(
        _ selector: VATSValue,
        _ camera: CameraConditionResolution
    ) -> UInt32? {
        switch selector {
        case .targetDistance: nil
        case .weapon: camera.weapon?.rawValue
        case .target: camera.targetBase?.rawValue
        case .action: camera.action
        case .weaponType: camera.weaponType
        case .projectileType: camera.projectileType
        case .delivery: camera.delivery
        case .castingType: camera.castingType
        }
    }

    private static func register(
        _ function: SideFunction,
        _ registry: inout ConditionFunctionRegistry,
        value: @escaping @Sendable (CameraConditionResolution, CameraConditionResolution.Side)
            -> Result<Float, ConditionFailure>
    ) {
        let entry = ConditionFunction(
            index: function.index,
            name: function.name,
            parameter1: .formID
        ) { call in
            let camera = call.context.camera
            guard camera.isAvailable else { return .failure(.unavailableData(.camera)) }
            return value(camera, function.side)
        }
        registry.register(entry)
    }
}

/// A camera condition function that asks about one side of the attacker.
nonisolated private struct SideFunction: Sendable {
    let index: UInt16
    let name: String
    let side: CameraConditionResolution.Side

    static let areaFree = [
        SideFunction(index: 515, name: "GetVATSRightAreaFree", side: .right),
        SideFunction(index: 516, name: "GetVATSLeftAreaFree", side: .left),
        SideFunction(index: 517, name: "GetVATSBackAreaFree", side: .back),
        SideFunction(index: 518, name: "GetVATSFrontAreaFree", side: .front)
    ]
    static let targetVisible = [
        SideFunction(index: 522, name: "GetVATSRightTargetVisible", side: .right),
        SideFunction(index: 523, name: "GetVATSLeftTargetVisible", side: .left)
    ]
}
