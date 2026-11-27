// What a set of effects being applied came from, for the conditions on their
// entries. See docs/engine/magic.md#conditions.

import Foundation
public import OpenSkyConditions

/// The cast behind the effects being applied right now.
nonisolated public struct MagicApplicationContext: Equatable, Sendable {
    /// Both hands cast the spell together, which `EffectWasDualCast` reads.
    public var isDualCast: Bool
    /// For an enchantment's hit: true restarts the target's running effect from the same
    /// item, false replaces it. Nil for anything else, which stacks.
    public var enchantmentRecast: Bool?

    public init(isDualCast: Bool = false) {
        self.isDualCast = isDualCast
    }
}

nonisolated extension MagicApplicationContext: ConditionResolution {
    public static let empty = MagicApplicationContext()
}
