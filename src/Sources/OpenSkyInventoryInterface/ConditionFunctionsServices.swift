// The vendor condition function, index from xEdit wbDefinitionsTES5.pas: 255
// GetOffersServicesNow. See docs/engine/vendor-factions.md#offers-services.

import Foundation
public import OpenSkyConditions
public import OpenSkyFormatsESM

/// Whether an actor offers services now, read when a condition asks.
nonisolated public struct ServicesConditionResolution: ConditionResolution, Sendable {
    public static let empty = ServicesConditionResolution(lookup: nil)

    private let lookup: (@MainActor @Sendable (ReferenceKey) -> Bool)?

    /// Conditions run on the main actor, as the whole simulation does.
    public init(lookup: (@MainActor @Sendable (ReferenceKey) -> Bool)?) {
        self.lookup = lookup
    }

    func offersServices(_ actor: ReferenceKey) -> Bool? {
        guard let lookup else { return nil }
        return MainActor.assumeIsolated { lookup(actor) }
    }
}

nonisolated public enum ConditionFunctionsServices {
    public static func installServices(_ registry: inout ConditionFunctionRegistry) {
        registry.register(ConditionFunction(index: 255, name: "GetOffersServicesNow") { call in
            call.referenceKey().flatMap { actor in
                guard
                    let offers = call.context[resolution: ServicesConditionResolution.self]
                        .offersServices(actor)
                else { return .failure(.unavailableData(.inventory)) }
                return .success(ConditionFunctions.isTrue(offers))
            }
        })
    }
}
