// What a set of effects being applied came from, for the conditions on their
// entries. See docs/engine/magic.md#conditions.

import Foundation
import OpenSkyConditions

/// The cast behind the effects being applied right now.
nonisolated public struct MagicApplicationContext: Equatable, Sendable {
    /// Both hands cast the spell together, which `EffectWasDualCast` reads.
    public var isDualCast: Bool

    public init(isDualCast: Bool = false) {
        self.isDualCast = isDualCast
    }
}

nonisolated extension MagicApplicationContext: ConditionResolution {
    public static let empty = MagicApplicationContext()
}

nonisolated extension ConditionContext {
    public var magicApplication: MagicApplicationContext {
        get { self[resolution: MagicApplicationContext.self] }
        set { self[resolution: MagicApplicationContext.self] = newValue }
    }
}
