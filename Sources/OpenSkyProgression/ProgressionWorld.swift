// The world side of the perk and progression domain: what `PerkCoordinator`
// and `ProgressionCoordinator` read from the running session. The app answers
// both; a test passes a fake. See docs/engine/coordinators.md.

import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyProgressionInterface

/// What `PerkCoordinator` reads from, and tells, the running world.
@MainActor
public protocol PerkWorld: AnyObject {
    /// Nil when `key` is not the player and not a resident actor.
    func actorValueHolder(for key: ReferenceKey) -> ActorValueHolder?
    func actorValue(at index: Int32, on holder: ActorValueHolder) -> Float?
    /// Called after every write. The cast loop keeps its own copy of the
    /// runtime, so it needs the new one.
    func perksChanged(_ runtime: PerkRuntime)
    /// Makes the constant abilities on `holder` match the perks it owns.
    func reconcileAbilities(on holder: ActorValueHolder, perks: PerkRuntime)
}

/// What `ProgressionCoordinator` reads from the running world.
@MainActor
public protocol ProgressionWorld: AnyObject {
    /// `.none` when nothing answers, so no armor skill is guessed.
    func wornArmor(of key: ReferenceKey) -> WornArmorProfile
    /// The live context a perk's own conditions are checked in.
    func conditionContext() -> ConditionContext
    /// One perk condition as the panel prints it.
    func conditionText(_ condition: Condition) -> String
}
