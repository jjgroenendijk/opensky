import Foundation
public import OpenSkyFormatsESM

/// Who pressed the use key on what, for one perk fragment.
nonisolated public struct PerkFragmentActivation: Equatable, Sendable {
    public let actor: ReferenceKey
    public let target: ReferenceKey

    public init(actor: ReferenceKey, target: ReferenceKey) {
        self.actor = actor
        self.target = target
    }
}
