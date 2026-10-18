// The seams scripts reach combat through. `CombatLoopRuntime` and
// `RagdollRuntime` conform, and the composition root hands them over as these
// protocols.

import OpenSkyActorsInterface
import OpenSkyFormatsESM

/// Starting, stopping, and reading an actor's fight.
@MainActor
public protocol CombatControlling: AnyObject {
    /// What `key` is doing in a fight right now.
    func activity(of key: ReferenceKey) -> ActorCombatActivity

    /// Who `key` fights now, or nil.
    func combatTarget(of key: ReferenceKey) -> ReferenceKey?

    /// Starts `actor` fighting `target`. Returns true when it was not already.
    @discardableResult
    func startCombat(_ actor: ReferenceKey, with target: ReferenceKey) -> Bool

    /// Stops `actor` fighting. Returns true when it was fighting.
    @discardableResult
    func stopCombat(_ actor: ReferenceKey) -> Bool
}

extension CombatControlling {
    public func combatTarget(of _: ReferenceKey) -> ReferenceKey? {
        nil
    }
}

/// Turning an actor whose health reached zero into a dead one.
@MainActor
public protocol DeathReporting: AnyObject {
    /// Marks `key` dead, crediting `killer`.
    ///
    /// - Returns: true when this call is what killed the actor.
    @discardableResult
    func noteZeroHealth(of key: ReferenceKey, killer: ReferenceKey?) -> Bool
}

extension DeathReporting {
    /// Marks `key` dead with no killer named.
    @discardableResult
    public func noteZeroHealth(of key: ReferenceKey) -> Bool {
        noteZeroHealth(of: key, killer: nil)
    }
}
