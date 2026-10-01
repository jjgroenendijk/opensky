// The world side of the magic domain: what `MagicCoordinator` reads from the
// running session. The app answers it; a test passes a fake.
// See docs/engine/coordinators.md.

import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyProgressionInterface
import OpenSkyWorldState

/// What `MagicCoordinator` reads from the running world. Skill uses pass
/// through to the session's skill runtime.
@MainActor
public protocol MagicWorld: AnyObject, SkillUseReporting {
    /// `GameClock.daysPassed`. Zero without a renderer.
    var gameDaysPassed: Float { get }
    /// Every inventory. Nil without an item runtime.
    var inventory: (any InventoryAccess)? { get }
    /// Every actor's equipment. Nil without an item runtime.
    var equipment: (any EquipmentAccess)? { get }

    /// Nil when `key` is not the player and not a resident actor.
    func actorValueHolder(for key: ReferenceKey) -> ActorValueHolder?
    /// The player and every resident actor: the set effects tick on.
    func regeneratingHolders() -> [ActorValueHolder]
    /// The resident actor nearest the camera, for the effects readout.
    func nearestActorValueHolder() -> ActorValueHolder?
    /// Every resident actor other than the player, in a stable order.
    func residentActorKeys() -> [ReferenceKey]
    func actorName(_ holder: ActorValueHolder) -> String
    func itemName(_ item: FormID) -> String
    /// The `SPLO` list of the player's race. Empty before a race is chosen.
    func playerRaceSpells() -> [FormID]

    /// Launches a spell projectile. False when the session cannot fly one.
    @discardableResult
    func fireSpellProjectile(_ payload: SpellPayload) -> Bool
    /// What `caster`'s aim ray reaches, out to `range`.
    func aimedSpellTarget(within range: Float, for caster: ReferenceKey) -> SpellAim
    /// One condition function's value as a readout word. The registry lives
    /// above this module, so the app runs the probe.
    func conditionText(of function: UInt16, parameter: UInt32, in context: ConditionContext)
        -> String
}
