// The lock condition function: 65 `GetLockLevel`, from xEdit dev-4.1.6
// Core/wbDefinitionsTES5.pas. The Novice to Master Locks perks gate their sweet-spot
// bonus on it. See docs/engine/locks.md.

import Foundation
import OpenSkyFormatsESM

/// Lock levels of the references a caller knows about, as XLOC bytes.
nonisolated public struct LockConditionResolution: Sendable {
    public static let empty = LockConditionResolution(levels: [:])

    private let levels: [ReferenceKey: UInt8]

    public init(levels: [ReferenceKey: UInt8]) {
        self.levels = levels
    }

    public func level(of key: ReferenceKey) -> UInt8? {
        levels[key]
    }
}

nonisolated extension LockConditionResolution: ConditionResolution {}

nonisolated extension ConditionContext {
    public var locks: LockConditionResolution {
        get { self[resolution: LockConditionResolution.self] }
        set { self[resolution: LockConditionResolution.self] = newValue }
    }
}

nonisolated extension ConditionFunctions {
    public static func installLock(_ registry: inout ConditionFunctionRegistry) {
        // "Returns the lock level of the calling reference."
        // (<https://ck.uesp.net/wiki/GetLockLevel>)
        registry.register(ConditionFunction(index: 65, name: "GetLockLevel") { call in
            call.referenceKey().flatMap { key in
                guard let level = call.context.locks.level(of: key) else {
                    return .failure(.unavailableData(.lock))
                }
                return .success(Float(level))
            }
        })
    }
}
