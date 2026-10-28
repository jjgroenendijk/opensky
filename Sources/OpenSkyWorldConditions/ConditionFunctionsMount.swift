// Mount and flight condition functions, indices from xEdit wbDefinitionsTES5.pas:
// 282 IsHorseStolen, 327 IsRidingMount, 339 IsPlayersLastRiddenMount, 714 IsBeingRidden, 633
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
    /// The mounts in the air, such as a tamed dragon.
    public let flyingMounts: Set<ReferenceKey>
    /// `GetFlyingState` of each actor that is not on the ground.
    public var flyingStates: [ReferenceKey: Int32] = [:]
    /// No actor flies in an interior.
    public var canFlyHere = false
    /// The actors the engine asks to land at once, by kind of landing.
    public var crashLandRequests: Set<ReferenceKey> = []
    public var hastyLandRequests: Set<ReferenceKey> = []

    public init(
        mounts: [ReferenceKey: ReferenceKey]?, playersLastMount: ReferenceKey?,
        flyingMounts: Set<ReferenceKey> = []
    ) {
        self.mounts = mounts
        self.playersLastMount = playersLastMount
        self.flyingMounts = flyingMounts
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
        // The CK wiki: "This function is a no-op and always returns 0."
        registry.register(ConditionFunction(index: 282, name: "IsHorseStolen") { _ in
            .success(0)
        })
        registry.register(ConditionFunction(index: 730, name: "IsOnFlyingMount") { call in
            let flying = call.context.mounts.flyingMounts
            return mount(call) { mounts, key, _ in
                Self.isTrue(mounts[key].map(flying.contains) ?? false)
            }
        })
        // 0 not flying, 1 taking off, 2 cruising, 3 hovering, 4 landing, 5 perched (CK
        // wiki "GetFlyingState - Actor").
        registry.register(ConditionFunction(index: 633, name: "GetFlyingState") { call in
            let states = call.context.mounts.flyingStates
            return mount(call) { _, key, _ in Float(states[key] ?? 0) }
        })
        registry.register(ConditionFunction(index: 731, name: "CanFlyHere") { call in
            let canFly = call.context.mounts.canFlyHere
            return mount(call) { _, _, _ in Self.isTrue(canFly) }
        })
        registry.register(ConditionFunction(index: 646, name: "GetIsCrashLandRequest") { call in
            let requests = call.context.mounts.crashLandRequests
            return mount(call) { _, key, _ in Self.isTrue(requests.contains(key)) }
        })
        registry.register(ConditionFunction(index: 647, name: "GetIsHastyLandRequest") { call in
            let requests = call.context.mounts.hastyLandRequests
            return mount(call) { _, key, _ in Self.isTrue(requests.contains(key)) }
        })
        // OpenSky has no flying patrol or fast travel.
        let flight: [String: UInt16] = [
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
