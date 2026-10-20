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
    /// The perks `holder`'s active magic effects apply (MGEF "Perk to Apply").
    func perksFromActiveEffects(on holder: ActorValueHolder) -> Set<ReferenceKey>
    /// Sets `stage` of `quest`, a FormID of `plugin`, as a script `SetStage` would.
    func setPerkQuestStage(_ stage: UInt16, quest: FormID, fromPlugin plugin: String)
}

extension PerkWorld {
    public func perksFromActiveEffects(on holder: ActorValueHolder) -> Set<ReferenceKey> {
        []
    }

    public func setPerkQuestStage(_: UInt16, quest _: FormID, fromPlugin _: String) {}
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
    /// The player's name and race as the skills menu card prints them.
    func playerIdentity() -> (name: String, race: String)
    /// The plugin string tables, for perk and skill names. Nil without them.
    func localizedStrings() -> LocalizedStrings?
    /// The nearest actor, when its class teaches a skill; nil otherwise.
    func nearestTrainer() -> TrainerOffer?
    func playerGold() -> Int
    /// Moves `gold` from the player to `trainer`. False when the player has too little.
    func payTrainer(_ gold: Int, to trainer: ReferenceKey) -> Bool
}

extension ProgressionWorld {
    public func nearestTrainer() -> TrainerOffer? {
        nil
    }

    public func playerGold() -> Int {
        0
    }

    public func payTrainer(_: Int, to _: ReferenceKey) -> Bool {
        false
    }

    public func playerIdentity() -> (name: String, race: String) {
        (name: "", race: "")
    }

    public func localizedStrings() -> LocalizedStrings? {
        nil
    }
}
