// The casting half of `CombatLoopWorld` for a world with no caster runtime.

public import OpenSkyBehavior
@testable public import OpenSkyCombat
@testable public import OpenSkyFormatsESM
public import OpenSkyGameData

/// A `CombatLoopWorld` whose actors have nothing to cast, so every fight is a
/// melee fight. A conformer gets the four casting members from here, and no actor
/// reacts to the player, so no hit counts as friendly fire.
@MainActor
public protocol NoCasterCombatWorld: CombatLoopWorld {}

extension NoCasterCombatWorld {
    /// A world without factions has no NPC foes.
    public func combatReaction(of _: ReferenceKey, toward _: ReferenceKey) -> ActorReaction? {
        nil
    }

    public func combatIsHostile(_: ReferenceKey, toward _: ReferenceKey) -> Bool {
        false
    }

    /// A world without destructible objects damages none.
    public func damageCombatDestructible(_: ReferenceKey, amount _: Float) {}

    /// A world that runs no NPC graphs writes nothing, and its graphs never hold a draw.
    public func writeCombatActorVariable(
        _: BehaviorVariableValue, named _: String, on _: ReferenceKey
    ) {}

    public func combatGraphIsEquipping(_: ReferenceKey) -> Bool {
        false
    }

    public func combatIsInKillMove(_: ReferenceKey) -> Bool {
        false
    }

    public func combatGraphIsAttackReady(_: ReferenceKey) -> Bool? {
        nil
    }

    /// A melee-only world looses no arrows.
    public func fireCombatArrow(_: CombatArrowShot) -> Bool {
        false
    }

    /// A world that reads no races carries no disease.
    public func combatAttackDisease(of _: ReferenceKey) -> ReferenceKey? {
        nil
    }

    public func combatDiseaseResist(of _: ReferenceKey) -> Float? {
        nil
    }

    public func contractCombatDisease(_: ReferenceKey, on _: ReferenceKey) -> Bool {
        false
    }

    public func sayCombatWarning(by _: ReferenceKey, to _: ReferenceKey) {}

    public func combatReaction(toPlayerOf _: ReferenceKey) -> ActorReaction? {
        nil
    }

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
