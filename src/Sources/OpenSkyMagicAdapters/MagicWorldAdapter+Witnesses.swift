import Foundation
import OpenSkyActorsInterface
import OpenSkyBehavior
import OpenSkyCells
import OpenSkyCombatInterface
public import OpenSkyConditions
import OpenSkyDialogueInterface
import OpenSkyEffects
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyFormatsMesh
public import OpenSkyGameData
public import OpenSkyInventoryInterface
public import OpenSkyMagic
public import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyNavigation
public import OpenSkyPhysics
import OpenSkyPlayer
public import OpenSkyProgressionInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// Witnesses that forward to the narrow parts of `MagicWorldAdapter`.
extension MagicWorldAdapter {
    @discardableResult
    public func staggerActor(_ key: ReferenceKey, magnitude: Float) -> Bool {
        archetypeEffects.staggerActor(key, magnitude: magnitude)
    }

    public func cloakTargets(around key: ReferenceKey, radius: Float) -> [ReferenceKey] {
        archetypeEffects.cloakTargets(around: key, radius: radius)
    }

    public func knock(
        _ targets: [ReferenceKey],
        awayFrom source: ReferenceKey,
        by payload: SpellPayload
    ) {
        archetypeEffects.knock(targets, awayFrom: source, by: payload)
    }

    public func actorHasKeyword(_ editorID: String, on holder: ActorValueHolder) -> Bool {
        archetypeEffects.actorHasKeyword(editorID, on: holder)
    }

    public func itemHasKeyword(_ editorID: String, on item: FormID) -> Bool {
        archetypeEffects.itemHasKeyword(editorID, on: item)
    }

    public func enchantment(_ base: ResolvedEnchantment, fits item: FormID) -> Bool {
        archetypeEffects.enchantment(base, fits: item)
    }

    @discardableResult
    public func fireSpellProjectile(_ payload: SpellPayload) -> Bool {
        spellDelivery.fireSpellProjectile(payload)
    }

    public func aimedSpellTarget(within range: Float, for caster: ReferenceKey) -> SpellAim {
        spellDelivery.aimedSpellTarget(within: range, for: caster)
    }

    public func shoutCooldown(recovery: Float, multiplier: Float) -> Float {
        ShoutCore.cooldown(recovery: recovery, multiplier: multiplier)
    }

    public func castReach(within range: Float) -> Float {
        spellDelivery.castReach(within: range)
    }

    public func actor(_ target: ReferenceKey, faces source: ReferenceKey) -> Bool {
        spellDelivery.actor(target, faces: source)
    }

    public func point(_ point: SIMD3<Float>, canSee target: ReferenceKey) -> Bool {
        spellDelivery.point(point, canSee: target)
    }

    public func keyword(editorID: String) -> ReferenceKey? {
        spellDelivery.keyword(editorID: editorID)
    }

    public func runeTriggers(for caster: ReferenceKey) -> [MeleeTarget] {
        spellDelivery.runeTriggers(for: caster)
    }

    public func spellHitCandidates() -> [MeleeTarget] {
        spellDelivery.spellHitCandidates()
    }

    public var isOutdoors: Bool {
        spellDelivery.isOutdoors
    }

    public func projectileProximity(of payload: SpellPayload) -> Float {
        spellDelivery.projectileProximity(of: payload)
    }

    public func commandActor(_ actor: ReferenceKey, for caster: ReferenceKey) {
        heldMagic.commandActor(actor, for: caster)
    }

    public func livingActors(near key: ReferenceKey, radius: Float) -> [ReferenceKey] {
        heldMagic.livingActors(near: key, radius: radius)
    }

    public func changeRace(of key: ReferenceKey, to race: FormID) -> Bool {
        heldMagic.changeRace(of: key, to: race)
    }

    public func markEaten(_ key: ReferenceKey) {
        heldMagic.markEaten(key)
    }

    public func aimRay(of key: ReferenceKey) -> MagicAimRay? {
        heldMagic.aimRay(of: key)
    }

    public func telekinesisTarget(for caster: ReferenceKey, within reach: Float) -> ReferenceKey? {
        heldMagic.telekinesisTarget(for: caster, within: reach)
    }

    public func heldBody(_ key: ReferenceKey) -> MagicHeldBody? {
        heldMagic.heldBody(key)
    }

    public func pushBody(_ key: ReferenceKey, impulse: SIMD3<Float>) {
        heldMagic.pushBody(key, impulse: impulse)
    }

    public func holdActor(_ actor: ReferenceKey, at point: SIMD3<Float>?) {
        heldMagic.holdActor(actor, at: point)
    }

    public func throwActor(_ actor: ReferenceKey, along direction: SIMD3<Float>, force: Float) {
        heldMagic.throwActor(actor, along: direction, force: force)
    }

    public func guidePath(for caster: ReferenceKey) -> MagicGuidePath {
        heldMagic.guidePath(for: caster)
    }

    @discardableResult
    public func placeHazard(_ hazard: ReferenceKey, at point: SIMD3<Float>) -> Bool {
        heldMagic.placeHazard(hazard, at: point)
    }

    public func perkChoices(
        at entryPoint: PerkEntryPoint,
        on key: ReferenceKey,
        subjects: PerkEvaluationSubjects,
        seams: ConditionContext
    ) -> [PerkEntryPointChoice] {
        summonedActors.perkChoices(at: entryPoint, on: key, subjects: subjects, seams: seams)
    }

    public func summonActor(_ base: FormID, at point: SIMD3<Float>?, for caster: ReferenceKey)
        -> ReferenceKey?
    {
        summonedActors.summonActor(base, at: point, for: caster)
    }

    public func reanimate(_ corpse: ReferenceKey, for caster: ReferenceKey) -> Bool {
        summonedActors.reanimate(corpse, for: caster)
    }

    public func stopCommandedActor(_ key: ReferenceKey) {
        summonedActors.stopCommandedActor(key)
    }

    public func releaseCommandedActor(_ actor: CommandedActor) {
        summonedActors.releaseCommandedActor(actor)
    }

    public func isActorDead(_ key: ReferenceKey) -> Bool {
        summonedActors.isActorDead(key)
    }

    public var shoutKnowledge: ShoutKnowledge {
        summonedActors.shoutKnowledge
    }

    public func changeShoutKnowledge(_ change: ShoutKnowledgeChange) {
        summonedActors.changeShoutKnowledge(change)
    }

    public var gameDaysPassed: Float {
        worldFacts.gameDaysPassed
    }

    public var inventory: (any InventoryAccess)? {
        worldFacts.inventory
    }

    public var equipment: (any EquipmentAccess)? {
        worldFacts.equipment
    }

    @discardableResult
    public func reportSkillUse(_ use: SkillUseEvent) -> Float {
        worldFacts.reportSkillUse(use)
    }

    public func actorValueHolder(for key: ReferenceKey) -> ActorValueHolder? {
        worldFacts.actorValueHolder(for: key)
    }

    public func regeneratingHolders() -> [ActorValueHolder] {
        worldFacts.regeneratingHolders()
    }

    public func nearestActorValueHolder() -> ActorValueHolder? {
        worldFacts.nearestActorValueHolder()
    }

    public func residentActorKeys() -> [ReferenceKey] {
        worldFacts.residentActorKeys()
    }

    public func actorName(_ holder: ActorValueHolder) -> String {
        worldFacts.actorName(holder)
    }

    public func displayName(of holder: ActorValueHolder) -> String? {
        worldFacts.displayName(of: holder)
    }

    public func itemName(_ item: FormID) -> String {
        worldFacts.itemName(item)
    }

    public func conditionText(
        of function: UInt16,
        parameter: UInt32,
        in context: ConditionContext
    ) -> String {
        worldFacts.conditionText(of: function, parameter: parameter, in: context)
    }

    public func playerAteIngredient(_ item: FormID) {
        worldFacts.playerAteIngredient(item)
    }

    public func postNotification(_ text: String) {
        worldFacts.postNotification(text)
    }

    public func announceSpellLearned(_ name: String) {
        worldFacts.announceSpellLearned(name)
    }

    public func raiseSkillFromBook(_ skill: Int32, points: Int) -> Int {
        worldFacts.raiseSkillFromBook(skill, points: points)
    }

    public func perkModified(
        _ value: Float,
        at entryPoint: PerkEntryPoint,
        on key: ReferenceKey,
        given conditions: (subjects: PerkEvaluationSubjects, seams: ConditionContext)
    ) -> Float {
        worldFacts.perkModified(value, at: entryPoint, on: key, given: conditions)
    }
}
