// Mount and flight condition functions, indices from xEdit wbDefinitionsTES5.pas:
// 327 IsRidingMount, 339 IsPlayersLastRiddenMount, 714 IsBeingRidden, 633
// GetFlyingState, 646 GetIsCrashLandRequest, 647 GetIsHastyLandRequest, 730
// IsOnFlyingMount, 731 CanFlyHere, 732 IsFlyingMountPatrolQueud, 733
// IsFlyingMountFastTravelling.
// See docs/engine/condition-functions-world.md#mounts-and-flight.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM

/// Who rides what: a rider on a horse's saddle bone, not a passenger on a cart.
nonisolated public struct MountConditionResolution: ConditionResolution, Sendable {
    public static let empty = MountConditionResolution(mounts: nil, playersLastMount: nil)

    /// Rider to mount. Nil when nothing was wired.
    public let mounts: [ReferenceKey: ReferenceKey]?
    public let playersLastMount: ReferenceKey?

    public init(mounts: [ReferenceKey: ReferenceKey]?, playersLastMount: ReferenceKey?) {
        self.mounts = mounts
        self.playersLastMount = playersLastMount
    }
}

nonisolated extension ConditionContext {
    public var mounts: MountConditionResolution {
        get { self[resolution: MountConditionResolution.self] }
        set { self[resolution: MountConditionResolution.self] = newValue }
    }
}

nonisolated extension ConditionFunctions {
    static func installMounts(_ registry: inout ConditionFunctionRegistry) {
        registry.register(ConditionFunction(index: 327, name: "IsRidingMount") { call in
            mount(call) { mounts, key, _ in Self.isTrue(mounts[key] != nil) }
        })
        registry.register(ConditionFunction(index: 714, name: "IsBeingRidden") { call in
            mount(call) { mounts, key, _ in Self.isTrue(mounts.values.contains(key)) }
        })
        registry.register(ConditionFunction(index: 339, name: "IsPlayersLastRiddenMount") { call in
            mount(call) { _, key, last in Self.isTrue(last == key) }
        })
        // OpenSky has no flying actors or flying mounts yet, so every flight read is the
        // grounded value: state 0 is FLY_STATE_NONE.
        let flight: [String: UInt16] = [
            "GetFlyingState": 633, "GetIsCrashLandRequest": 646,
            "GetIsHastyLandRequest": 647, "IsOnFlyingMount": 730, "CanFlyHere": 731,
            "IsFlyingMountPatrolQueud": 732, "IsFlyingMountFastTravelling": 733
        ]
        for (name, index) in flight.sorted(by: { $0.key < $1.key }) {
            registry.register(ConditionFunction(index: index, name: name) { call in
                mount(call) { _, _, _ in 0 }
            })
        }
    }

    private static func mount(
        _ call: ConditionCall,
        read: ([ReferenceKey: ReferenceKey], ReferenceKey, ReferenceKey?) -> Float
    ) -> Result<Float, ConditionFailure> {
        call.referenceKey().flatMap { key in
            let resolution = call.context.mounts
            guard let mounts = resolution.mounts else {
                return .failure(.unavailableData(.mount))
            }
            return .success(read(mounts, key.namingPlayer, resolution.playersLastMount))
        }
    }
}
