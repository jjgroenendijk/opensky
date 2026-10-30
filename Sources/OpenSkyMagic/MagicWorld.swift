// The world side of the magic domain: what `MagicCoordinator` reads from the
// running session. The app answers it; a test passes a fake.
// See docs/engine/coordinators.md.

import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyPhysics
import OpenSkyProgressionInterface
import simd

/// What `MagicCoordinator` reads from the running world. Skill uses pass
/// through to the session's skill runtime.
@MainActor
public protocol MagicWorld: AnyObject, SkillUseReporting, MagicArchetypeWorld {
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

    /// Launches a spell projectile. False when the session cannot fly one.
    @discardableResult
    func fireSpellProjectile(_ payload: SpellPayload) -> Bool
    /// What `caster`'s aim ray reaches, out to `range`.
    func aimedSpellTarget(within range: Float, for caster: ReferenceKey) -> SpellAim
    /// Living actors hostile to `key` within `radius` world units of it.
    func cloakTargets(around key: ReferenceKey, radius: Float) -> [ReferenceKey]
    /// Whether `holder`'s base record or race carries the keyword `editorID`.
    func actorHasKeyword(_ editorID: String, on holder: ActorValueHolder) -> Bool
    /// Whether `item`'s base record carries the keyword named `editorID`.
    func itemHasKeyword(_ editorID: String, on item: FormID) -> Bool
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
    /// Whether `base`'s worn restriction list names one of `item`'s keywords.
    func enchantment(_ base: ResolvedEnchantment, fits item: FormID) -> Bool
    /// The player's shouts and words, from the script state the natives write.
    var shoutKnowledge: ShoutKnowledge { get }
    func changeShoutKnowledge(_ change: ShoutKnowledgeChange)
    /// The `KYWD` named `editorID` in the load order.
    func keyword(editorID: String) -> ReferenceKey?
    /// Living actors hostile to `caster`, which set off its runes.
    func runeTriggers(for caster: ReferenceKey) -> [MeleeTarget]
    /// Every actor a spell landing in the world can reach.
    func spellHitCandidates() -> [MeleeTarget]
    /// The `explosionProximity` of the payload's `PROJ`; zero when it has none.
    func projectileProximity(of payload: SpellPayload) -> Float
    /// The player stands in an exterior cell, where runes reach farther.
    var isOutdoors: Bool { get }
    /// `key`'s passing effects at an entry point that picks a spell, highest priority first.
    func perkChoices(
        at entryPoint: PerkEntryPoint,
        on key: ReferenceKey,
        subjects: PerkEvaluationSubjects,
        seams: ConditionContext
    ) -> [PerkEntryPointChoice]
    /// Places a new actor of `base` at `point`, or beside `caster` when nil.
    func summonActor(_ base: FormID, at point: SIMD3<Float>?, for caster: ReferenceKey)
        -> ReferenceKey?
    /// Raises the dead `corpse`. False when it is not dead.
    func reanimate(_ corpse: ReferenceKey, for caster: ReferenceKey) -> Bool
    /// A summon fades away; a reanimated actor falls dead again.
    func releaseCommandedActor(_ actor: CommandedActor)
    /// A dismissed summon stops fighting while it fades.
    func stopCommandedActor(_ key: ReferenceKey)
    func isActorDead(_ key: ReferenceKey) -> Bool
    /// Every cast, for the Papyrus `OnSpellCast` event.
    func noteSpellCast(_ spell: ReferenceKey, by caster: ReferenceKey)
    /// The actor rides a dragon in the air (`IsOnFlyingMount`).
    func isOnFlyingMount(_ key: ReferenceKey) -> Bool
}

extension MagicWorld {
    /// A session with no mounts has no rider in the air.
    public func isOnFlyingMount(_: ReferenceKey) -> Bool {
        false
    }

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

    /// A session with no scripts hears no cast.
    public func noteSpellCast(_: ReferenceKey, by _: ReferenceKey) {}

    public func postNotification(_: String) {}

    /// A session with no keyword index finds none.
    public func itemHasKeyword(_: String, on _: FormID) -> Bool {
        false
    }

    /// A session with no placement treats every actor as facing every source.
    public func actor(_: ReferenceKey, faces _: ReferenceKey) -> Bool {
        true
    }

    /// A session with no form lists restricts nothing.
    public func enchantment(_: ResolvedEnchantment, fits _: FormID) -> Bool {
        true
    }

    /// A session with no scripts knows no shout.
    public var shoutKnowledge: ShoutKnowledge {
        ShoutKnowledge()
    }

    public func changeShoutKnowledge(_: ShoutKnowledgeChange) {}

    /// A session with no keyword index finds none, so no spell is a rune.
    public func keyword(editorID _: String) -> ReferenceKey? {
        nil
    }

    public func runeTriggers(for _: ReferenceKey) -> [MeleeTarget] {
        []
    }

    public func spellHitCandidates() -> [MeleeTarget] {
        []
    }

    public func projectileProximity(of _: SpellPayload) -> Float {
        0
    }

    public var isOutdoors: Bool {
        false
    }

    public func perkChoices(
        at _: PerkEntryPoint,
        on _: ReferenceKey,
        subjects _: PerkEvaluationSubjects,
        seams _: ConditionContext
    ) -> [PerkEntryPointChoice] {
        []
    }

    /// A session with no world places no actor.
    public func summonActor(_: FormID, at _: SIMD3<Float>?, for _: ReferenceKey)
        -> ReferenceKey?
    {
        nil
    }

    public func reanimate(_: ReferenceKey, for _: ReferenceKey) -> Bool {
        false
    }

    public func releaseCommandedActor(_: CommandedActor) {}

    public func stopCommandedActor(_: ReferenceKey) {}

    public func isActorDead(_: ReferenceKey) -> Bool {
        false
    }

    /// A session with no collision has no walls.
    public func point(_: SIMD3<Float>, canSee _: ReferenceKey) -> Bool {
        true
    }
}
