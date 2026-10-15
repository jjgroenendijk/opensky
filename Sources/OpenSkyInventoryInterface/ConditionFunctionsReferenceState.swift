// Reference-state condition functions, indices from xEdit wbDefinitionsTES5.pas: 5
// GetLocked, 157 GetOpenState, 624 GetInContainer, 718 IsUnlockedDoor, 726
// DoesNotExist. See docs/engine/condition-functions-world.md#reference-state.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM

/// One placed reference as these functions see it: plugin baseline plus runtime deltas.
nonisolated public struct ReferenceConditionFacts: Equatable, Sendable {
    /// Nil when the reference has no lock.
    public var lock: ReferenceLockState?
    public var isOpen: Bool
    /// A DOOR base.
    public var isDoor: Bool
    /// Picked up or otherwise deleted at runtime.
    public var isDeleted: Bool

    public init(
        lock: ReferenceLockState? = nil,
        isOpen: Bool = false,
        isDoor: Bool = false,
        isDeleted: Bool = false
    ) {
        self.lock = lock
        self.isOpen = isOpen
        self.isDoor = isDoor
        self.isDeleted = isDeleted
    }

    /// `GetOpenState` codes: 1 open, 3 closed. OpenSky has no opening or closing phase,
    /// so 2 and 4 never occur, as for the `GetOpenState` native.
    public var openState: Float {
        isOpen ? 1 : 3
    }
}

nonisolated public struct ReferenceConditionResolution: ConditionResolution, Sendable {
    public static let empty = ReferenceConditionResolution(facts: nil)

    private let facts: [ReferenceKey: ReferenceConditionFacts]?

    public init(facts: [ReferenceKey: ReferenceConditionFacts]?) {
        self.facts = facts
    }

    public var isAvailable: Bool {
        facts != nil
    }

    public func facts(of key: ReferenceKey) -> ReferenceConditionFacts? {
        facts?[key]
    }
}

nonisolated extension ConditionContext {
    public var referenceFacts: ReferenceConditionResolution {
        get { self[resolution: ReferenceConditionResolution.self] }
        set { self[resolution: ReferenceConditionResolution.self] = newValue }
    }
}

nonisolated extension ConditionFunctions {
    public static func installReferenceState(_ registry: inout ConditionFunctionRegistry) {
        registry.register(ConditionFunction(index: 5, name: "GetLocked") { call in
            referenceFacts(call) { Self.isTrue($0.lock?.isLocked == true) }
        })
        registry.register(ConditionFunction(index: 157, name: "GetOpenState") { call in
            referenceFacts(call) { $0.openState }
        })
        registry.register(ConditionFunction(index: 718, name: "IsUnlockedDoor") { call in
            referenceFacts(call) { Self.isTrue($0.isDoor && $0.lock?.isLocked != true) }
        })
        registry.register(ConditionFunction(index: 726, name: "DoesNotExist") { call in
            referenceFacts(call) { Self.isTrue($0.isDeleted) }
        })
        // An item a container holds is a count, never a reference, so no placed
        // reference is inside a container.
        registry.register(ConditionFunction(
            index: 624, name: "GetInContainer", parameter1: .formID
        ) { call in
            guard let parameter = call.parameter1, call.referenceEntry(parameter.asFormID) != nil
            else { return .failure(.unresolvedParameter(624)) }
            return referenceFacts(call) { _ in 0 }
        })
    }

    private static func referenceFacts(
        _ call: ConditionCall,
        read: (ReferenceConditionFacts) -> Float
    ) -> Result<Float, ConditionFailure> {
        call.referenceKey().flatMap { key in
            guard let facts = call.context.referenceFacts.facts(of: key) else {
                return .failure(.unavailableData(.reference))
            }
            return .success(read(facts))
        }
    }
}
