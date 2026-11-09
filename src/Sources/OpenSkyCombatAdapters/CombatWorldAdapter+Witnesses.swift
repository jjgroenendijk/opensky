import OpenSkyActorPresentation
import OpenSkyActors
public import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyAudio
public import OpenSkyBehavior
import OpenSkyCamera
import OpenSkyCells
public import OpenSkyCombat
public import OpenSkyCombatInterface
public import OpenSkyConditions
import OpenSkyCrime
import OpenSkyDialogue
import OpenSkyDialogueInterface
import OpenSkyEffects
import OpenSkyFactions
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyInventory
public import OpenSkyInventoryInterface
import OpenSkyMagic
public import OpenSkyMagicInterface
import OpenSkyMenus
import OpenSkyNavigation
import OpenSkyPerception
import OpenSkyPerceptionInterface
public import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyProgression
public import OpenSkyProgressionInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyScripting
import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
public import OpenSkyWorldState
import simd

extension CombatWorldAdapter: CombatWorld {}

/// Witnesses that forward to the narrow parts of `CombatWorldAdapter`.
extension CombatWorldAdapter {
    public func castingFacts(of key: ReferenceKey) -> CombatCastingFacts? {
        spellCasts.castingFacts(of: key)
    }

    @discardableResult
    public func shout(_ spell: ReferenceKey, by key: ReferenceKey) -> Bool {
        spellCasts.shout(spell, by: key)
    }

    @discardableResult
    public func beginCast(_ spell: ReferenceKey, by key: ReferenceKey) -> Bool {
        spellCasts.beginCast(spell, by: key)
    }

    @discardableResult
    public func releaseCast(by key: ReferenceKey) -> Bool {
        spellCasts.releaseCast(by: key)
    }

    public func cancelCast(by key: ReferenceKey) {
        spellCasts.cancelCast(by: key)
    }

    public func impactMaterial(of actor: ReferenceKey) -> FormID? {
        impactEffects.impactMaterial(of: actor)
    }

    public func actorFlies(_ actor: ReferenceKey) -> Bool {
        impactEffects.actorFlies(actor)
    }

    public func canBeKilled(_ target: ReferenceKey, by attacker: ReferenceKey) -> Bool {
        impactEffects.canBeKilled(target, by: attacker)
    }

    public func startKillMove(_ attempt: KillMoveAttempt) -> Bool {
        impactEffects.startKillMove(attempt)
    }

    public func isInKillMove(_ key: ReferenceKey) -> Bool {
        impactEffects.isInKillMove(key)
    }

    @discardableResult
    public func reportScriptHit(_ hit: ScriptHitEvent) -> Int {
        reports.reportScriptHit(hit)
    }

    @discardableResult
    public func reportSkillUse(_ use: SkillUseEvent) -> Float {
        reports.reportSkillUse(use)
    }

    @discardableResult
    public func applySpellHit(_ hit: SpellHit) -> SpellHitReport {
        reports.applySpellHit(hit)
    }

    @discardableResult
    public func applyWeaponEnchantment(_ hit: WeaponEnchantmentHit) -> WeaponEnchantmentReport? {
        reports.applyWeaponEnchantment(hit)
    }

    public func applyWeaponPoison(_ hit: WeaponPoisonHit) {
        reports.applyWeaponPoison(hit)
    }

    @discardableResult
    public func applyWeaponEnhancement(attacker: ReferenceKey, target: ReferenceKey) -> Int {
        reports.applyWeaponEnhancement(attacker: attacker, target: target)
    }

    public func spellLanded(_ payload: SpellPayload, at point: SIMD3<Float>) {
        reports.spellLanded(payload, at: point)
    }

    public var playerAttacker: MeleeAttacker? {
        actorFacts.playerAttacker
    }

    public var playerShooter: ProjectileShooter? {
        actorFacts.playerShooter
    }

    public func residentActors() -> [CombatActorObservation] {
        actorFacts.residentActors()
    }

    public func residentActor(key: ReferenceKey) -> CombatActorObservation? {
        actorFacts.residentActor(key: key)
    }

    public func selectedActor() -> ReferenceKey? {
        actorFacts.selectedActor()
    }

    public func hostility(of key: ReferenceKey) -> ActorHostility {
        actorFacts.hostility(of: key)
    }

    @discardableResult
    public func setHostility(_ hostility: ActorHostility, on key: ReferenceKey) -> Bool {
        actorFacts.setHostility(hostility, on: key)
    }

    public func awareness(
        of observer: ReferenceKey,
        toward target: ReferenceKey
    ) -> CombatAwareness {
        actorFacts.awareness(of: observer, toward: target)
    }

    public func actorValues(of key: ReferenceKey) -> ((Int32) -> Float?)? {
        actorFacts.actorValues(of: key)
    }

    public func perkMultiplier(at entryPoint: PerkEntryPoint, on key: ReferenceKey) -> Float {
        actorFacts.perkMultiplier(at: entryPoint, on: key)
    }

    public func perkModified(
        _ value: Float,
        at entryPoint: PerkEntryPoint,
        on key: ReferenceKey,
        subjects: PerkEvaluationSubjects,
        seams: ConditionContext
    ) -> Float {
        actorFacts.perkModified(value, at: entryPoint, on: key, subjects: subjects, seams: seams)
    }

    public func perkChoices(
        at entryPoint: PerkEntryPoint,
        on key: ReferenceKey,
        subjects: PerkEvaluationSubjects,
        seams: ConditionContext
    ) -> [PerkEntryPointChoice] {
        actorFacts.perkChoices(at: entryPoint, on: key, subjects: subjects, seams: seams)
    }

    public var isInInterior: Bool {
        actorFacts.isInInterior
    }

    public func combatStyle(of key: ReferenceKey) -> CombatStyleTuning? {
        actorFacts.combatStyle(of: key)
    }

    public func health(of key: ReferenceKey) -> (current: Float, maximum: Float)? {
        actorFacts.health(of: key)
    }

    @discardableResult
    public func damageHealth(by amount: Float, of key: ReferenceKey) -> Bool {
        actorFacts.damageHealth(by: amount, of: key)
    }

    public func ownsPerk(editorID: String, on key: ReferenceKey) -> Bool {
        actorFacts.ownsPerk(editorID: editorID, on: key)
    }

    public func damageStamina(by amount: Float, of key: ReferenceKey) {
        actorFacts.damageStamina(by: amount, of: key)
    }

    public func pauseBowZoomStamina() {
        actorFacts.pauseBowZoomStamina()
    }

    public func level(of key: ReferenceKey) -> Int? {
        actorFacts.level(of: key)
    }

    public func reaction(of observer: ReferenceKey, toward target: ReferenceKey) -> ActorReaction? {
        actorFacts.reaction(of: observer, toward: target)
    }

    public var equipment: (any EquipmentAccess)? {
        gear.equipment
    }

    public func magicInfluence(of key: ReferenceKey) -> ActorMagicInfluence {
        gear.magicInfluence(of: key)
    }

    public func enchantmentProfile(of item: FormID) -> ItemEnchantmentProfile? {
        gear.enchantmentProfile(of: item)
    }

    public func temperLevel(of item: FormID) -> Int32 {
        gear.temperLevel(of: item)
    }

    public func equippedItems(of key: ReferenceKey) -> [(item: FormID, temperLevel: Int32)] {
        gear.equippedItems(of: key)
    }

    public func hasReadiedSpell(in hand: SpellHand) -> Bool {
        gear.hasReadiedSpell(in: hand)
    }

    public func playerCarriedItems() -> [FormID] {
        gear.playerCarriedItems()
    }

    @discardableResult
    public func addItem(_ item: FormID, count: Int32, to key: ReferenceKey) -> Bool {
        gear.addItem(item, count: count, to: key)
    }

    @discardableResult
    public func removeOneFromPlayer(_ item: FormID) -> Bool {
        gear.removeOneFromPlayer(item)
    }

    public func packageIgnoresCombat(_ key: ReferenceKey) -> Bool {
        motion.packageIgnoresCombat(key)
    }

    public func isKnockedDown(_ key: ReferenceKey) -> Bool {
        motion.isKnockedDown(key)
    }

    @discardableResult
    public func moveActor(_ key: ReferenceKey, to point: SIMD3<Float>) -> Bool {
        motion.moveActor(key, to: point)
    }

    @discardableResult
    public func moveActor(
        _ key: ReferenceKey,
        to point: SIMD3<Float>,
        gait: LocomotionGait?
    ) -> Bool {
        motion.moveActor(key, to: point, gait: gait)
    }

    public func faceActor(_ key: ReferenceKey, toward point: SIMD3<Float>) {
        motion.faceActor(key, toward: point)
    }

    public func stopActor(_ key: ReferenceKey) {
        motion.stopActor(key)
    }

    public func resumePackage(for key: ReferenceKey) {
        motion.resumePackage(for: key)
    }

    @discardableResult
    public func raisePlayerGraphEvent(_ name: String) -> Bool {
        motion.raisePlayerGraphEvent(name)
    }

    public func writePlayerGraphVariable(_ value: BehaviorVariableValue, named name: String) {
        motion.writePlayerGraphVariable(value, named: name)
    }

    @discardableResult
    public func raiseActorGraphEvent(_ name: String, on key: ReferenceKey) -> Bool {
        motion.raiseActorGraphEvent(name, on: key)
    }

    public func writeActorGraphVariable(
        _ value: BehaviorVariableValue, named name: String, on key: ReferenceKey
    ) {
        motion.writeActorGraphVariable(value, named: name, on: key)
    }

    public func recordHealthHit(_ hit: CombatHitRecord, on key: ReferenceKey) {
        motion.recordHealthHit(hit, on: key)
    }

    public func impact(dataSet: FormID, material: FormID?) -> ResolvedMeleeImpact? {
        game.worldData?.footstepStore.flatMap {
            MeleeImpactResolver(footsteps: $0).resolve(dataSet: dataSet, material: material)
        }
    }

    public func playImpact(_ impact: ResolvedMeleeImpact, at position: SIMD3<Float>) {
        motion.playImpact(impact, at: position)
    }

    public func playImpact(_ impact: ResolvedMeleeImpact, at position: SIMD3<Float>, gain: Float) {
        motion.playImpact(impact, at: position, gain: gain)
    }

    public func sweep(_ query: ShapeSweepQuery) -> ShapeSweepHit? {
        motion.sweep(query)
    }

    public func residentCells() -> Set<CellSceneLocation> {
        motion.residentCells()
    }

    public func spawn(
        _ reference: ReferenceSpawnState,
        in location: CellSceneLocation
    ) -> ReferenceKey? {
        motion.spawn(reference, in: location)
    }

    public var bodyTransients: CombatTransientCounts {
        motion.bodyTransients
    }

    public func trimBodyTransients(to limits: CombatTransientLimits) -> CombatTransientCounts {
        motion.trimBodyTransients(to: limits)
    }

    public func run(_ commands: [CombatCommand]) {
        outcomes.run(commands)
    }
}
