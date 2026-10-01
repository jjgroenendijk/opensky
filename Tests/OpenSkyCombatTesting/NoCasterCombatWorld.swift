// The casting half of `CombatLoopWorld` for a world with no caster runtime.

@testable import OpenSkyCombat
@testable import OpenSkyFormatsESM

/// A `CombatLoopWorld` whose actors have nothing to cast, so every fight is a
/// melee fight. A conformer gets the four casting members from here.
@MainActor
public protocol NoCasterCombatWorld: CombatLoopWorld {}

extension NoCasterCombatWorld {
    public func combatCasting(of _: ReferenceKey) -> CombatCastingProfile {
        .none
    }

    @discardableResult
    public func beginCombatCast(_: CombatSpellOption, by _: ReferenceKey) -> Bool {
        false
    }

    @discardableResult
    public func releaseCombatCast(_: CombatSpellOption, by _: ReferenceKey) -> Bool {
        false
    }

    public func cancelCombatCast(by _: ReferenceKey) {}
}
