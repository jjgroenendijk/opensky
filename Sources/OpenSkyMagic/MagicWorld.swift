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
import simd

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
    /// Living actors hostile to `key` within `radius` world units of it.
    func cloakTargets(around key: ReferenceKey, radius: Float) -> [ReferenceKey]
    /// Whether `holder`'s base record or race carries the keyword `editorID`.
    func actorHasKeyword(_ editorID: String, on holder: ActorValueHolder) -> Bool
    /// One condition function's value as a readout word. The registry lives
    /// above this module, so the app runs the probe.
    func conditionText(of function: UInt16, parameter: UInt32, in context: ConditionContext)
        -> String
    /// What `key`'s perks make of `value`, with `subjects` bound and `seams` laid over
    /// the live conditions.
    func perkModified(
        _ value: Float,
        at entryPoint: PerkEntryPoint,
        on key: ReferenceKey,
        subjects: PerkEvaluationSubjects,
        seams: ConditionContext
    ) -> Float
    /// Raises the player's skill at actor value index `skill` by `points` levels, for
    /// a read skill book. Returns how many levels it rose.
    @discardableResult
    func raiseSkillFromBook(_ skill: Int32, points: Int) -> Int
    /// The player ate `item`, an ingredient, which teaches its first effect.
    func playerAteIngredient(_ item: FormID)
    /// Whether `target` faces `source` within a ward's front arc.
    func actor(_ target: ReferenceKey, faces source: ReferenceKey) -> Bool
    /// Whether no placed geometry stands between `point` and `target`.
    func point(_ point: SIMD3<Float>, canSee target: ReferenceKey) -> Bool
    /// Shows `text` in the HUD's notification line.
    func postNotification(_ text: String)
}

extension MagicWorld {
    /// A session with no perks leaves every value as authored.
    public func perkModified(
        _ value: Float,
        at _: PerkEntryPoint,
        on _: ReferenceKey,
        subjects _: PerkEvaluationSubjects,
        seams _: ConditionContext
    ) -> Float {
        value
    }

    /// A session with no progression raises nothing.
    @discardableResult
    public func raiseSkillFromBook(_: Int32, points _: Int) -> Int {
        0
    }

    /// A session with no alchemy learns nothing.
    public func playerAteIngredient(_: FormID) {}

    public func postNotification(_: String) {}

    /// A session with no placement treats every actor as facing every source.
    public func actor(_: ReferenceKey, faces _: ReferenceKey) -> Bool {
        true
    }

    /// A session with no collision has no walls.
    public func point(_: SIMD3<Float>, canSee _: ReferenceKey) -> Bool {
        true
    }
}
