// The app's answers to `CombatWorld`: each one a plain read of, or a write to,
// a session system the view controller owns.

import OpenSkyActors
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyAudio
import OpenSkyBehavior
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyCrime
import OpenSkyDialogue
import OpenSkyFactions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMagic
import OpenSkyMagicInterface
import OpenSkyMenus
import OpenSkyNavigation
import OpenSkyPerception
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyProgressionInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyWorld
import OpenSkyWorldState
import simd

extension CombatWorldAdapter: CombatWorld {
    /// Every landed blow passes here, so assault is noticed in one place.
    @discardableResult
    func reportScriptHit(_ hit: ScriptHitEvent) -> Int {
        let wasHostile = hostility(of: hit.target) == .hostile
        game.crime.reportAssault(on: hit.target, wasHostile: wasHostile, aggressor: hit.aggressor)
        if hit.aggressor == .player {
            game.perception.runtime?.noteAttack(by: .player)
        }
        game.scripts.bridge?.recordHit(hit, targetWasHostile: wasHostile)
        speakCombatLines(for: hit)
        return game.scripts.runtime?.queueOnHit(hit) ?? 0
    }

    /// An NPC aggressor may call out its attack and an NPC target its hurt, each held back
    /// by its own `SpeechTimerSettings` window and chance. A hit below
    /// `fCombatSpeakHitThreshold` of the target's health stays silent; a spell hit carries
    /// no damage yet, so it is not held back.
    private func speakCombatLines(for hit: ScriptHitEvent) {
        let now = game.storyWorld.sceneSeconds
        let maximum = health(of: hit.target)?.maximum ?? 0
        let hurtSpeaks = hit.delivery == .spell
            || game.dialogue.speechTimers.hitSpeaks(damage: hit.damage, maximumHealth: maximum)
        var lines: [(NPCSpeechLine, ReferenceKey)] = [(.combatAttack, hit.aggressor)]
        if hurtSpeaks {
            lines.append((.combatHit, hit.target))
        }
        for (line, speaker) in lines where speaker != .player {
            guard
                let id = game.dialogue.combatLine(line, speaker: speaker, now: now),
                let info = game.dialogue.runtime?.dialogue.info(id)
            else { continue }
            let seconds = game.storyWorld.lineDuration(of: info, speaker: speaker)
            game.storyWorld.speak(
                info: id, speaker: speaker, lookAt: nil,
                seconds: seconds ?? SceneLine.defaultSeconds
            )
        }
    }

    @discardableResult
    func reportSkillUse(_ use: SkillUseEvent) -> Float {
        game.progression.reportSkillUse(use)
    }

    @discardableResult
    func applySpellHit(_ hit: SpellHit) -> SpellHitReport {
        game.magicWorld.applySpellHit(hit)
    }

    @discardableResult
    func applyWeaponEnchantment(_ hit: WeaponEnchantmentHit) -> WeaponEnchantmentReport? {
        game.magic.applyWeaponEnchantment(hit)
    }

    @discardableResult
    func applyWeaponPoison(_ hit: WeaponPoisonHit) -> WeaponPoisonReport? {
        game.magic.applyWeaponPoison(hit)
    }

    @discardableResult
    func applyWeaponEnhancement(attacker: ReferenceKey, target: ReferenceKey) -> Int {
        game.magic.applyWeaponEnhancement(attacker: attacker, target: target)
    }

    func spellLanded(_ payload: SpellPayload, at point: SIMD3<Float>) {
        game.magic.spellLanded(payload, at: point)
    }

    var playerAttacker: MeleeAttacker? {
        guard let gameSession = game.gameSession else { return nil }
        return MeleeAttacker(
            key: .player,
            feet: gameSession.walkController.feetPosition,
            capsule: gameSession.walkController.capsule,
            facing: gameSession.freeFlyCamera.yaw
        )
    }

    var playerShooter: ProjectileShooter? {
        guard let gameSession = game.gameSession else { return nil }
        return ProjectileShooter(
            key: .player,
            origin: gameSession.freeFlyCamera.position,
            aim: gameSession.freeFlyCamera.forward,
            isFirstPerson: gameSession.movementMode != .thirdPerson,
            location: game.streamer?.currentCellLocation
        )
    }

    func residentActors() -> [CombatActorObservation] {
        game.actorWorld.combatActors()
    }

    func residentActor(key: ReferenceKey) -> CombatActorObservation? {
        game.actorWorld.combatActor(key: key)
    }

    /// The nearest resident actor: the same selector the actor-value controls use.
    func selectedActor() -> ReferenceKey? {
        game.actorWorld.nearestActorValueHolder()?.key
    }

    func hostility(of key: ReferenceKey) -> ActorHostility {
        game.factions.hostility(of: key)
    }

    @discardableResult
    func setHostility(_ hostility: ActorHostility, on key: ReferenceKey) -> Bool {
        game.factions.setHostility(hostility, on: key)
    }

    func awareness(of observer: ReferenceKey, toward target: ReferenceKey) -> CombatAwareness {
        guard let runtime = game.perception.runtime else { return .unaware }
        let pair = runtime.state(observer: observer, target: target)
        return CombatAwareness(state: pair.state, lastKnownPosition: pair.lastKnownPosition)
    }

    func actorValues(of key: ReferenceKey) -> ((Int32) -> Float?)? {
        guard
            let runtime = game.actorValues.runtime,
            let holder = game.actorWorld.actorValueHolder(for: key)
        else { return nil }
        return { runtime.value(at: $0, on: holder) }
    }

    func perkMultiplier(at entryPoint: PerkEntryPoint, on key: ReferenceKey) -> Float {
        game.perks.multiplier(at: entryPoint, on: key)
    }

    func perkModified(
        _ value: Float,
        at entryPoint: PerkEntryPoint,
        on key: ReferenceKey,
        subjects: PerkEvaluationSubjects,
        seams: ConditionContext
    ) -> Float {
        game.perks.modified(
            value,
            at: entryPoint,
            on: key,
            subjects: { _ in subjects },
            seams: seams
        )
    }

    func perkChoices(
        at entryPoint: PerkEntryPoint,
        on key: ReferenceKey,
        subjects: PerkEvaluationSubjects,
        seams: ConditionContext
    ) -> [PerkEntryPointChoice] {
        game.perks.choices(at: entryPoint, on: key, subjects: { _ in subjects }, seams: seams)
    }

    var isInInterior: Bool {
        game.streamer?.interiorScene != nil
    }

    /// ZNAM after template inheritance, read through the load-order CSTY store.
    func combatStyle(of key: ReferenceKey) -> CombatStyleTuning? {
        guard
            case let .actor(base)? = game.actorWorld.actorValueHolder(for: key)?.subject,
            let resolver = game.worldData?.actorValueBaselines?
                .resolver,
            let link = try? resolver.templates
                .rolling(game.worldState.leveledRoll(
                    of: key, base: base, with: resolver.templates.leveling
                ))
                .resolveCombatStyle(base: base).value,
            let style = game.worldData?.presentationRecords?
                .combatStyles.resolve(link, fromPlugin: resolver.pluginName)
        else { return nil }
        return CombatStyleTuning(style: style.record)
    }

    func health(of key: ReferenceKey) -> (current: Float, maximum: Float)? {
        guard
            let runtime = game.actorValues.runtime,
            let holder = game.actorWorld.actorValueHolder(for: key)
        else { return nil }
        return (runtime.current(of: holder).health, runtime.maximums(of: holder).health)
    }

    @discardableResult
    func damageHealth(by amount: Float, of key: ReferenceKey) -> Bool {
        guard
            let runtime = game.actorValues.runtime,
            let holder = game.actorWorld.actorValueHolder(for: key)
        else { return false }
        runtime.damage(.health, by: amount, on: holder)
        return true
    }

    func ownsPerk(editorID: String, on key: ReferenceKey) -> Bool {
        guard
            let perk = game.perks.runtime?.perks.perk(editorID: editorID),
            let owned = game.perks.ownership(of: key)
        else { return false }
        return owned.contains(ReferenceKey(resolved: perk.id))
    }

    func damageStamina(by amount: Float, of key: ReferenceKey) {
        guard
            let runtime = game.actorValues.runtime,
            let holder = game.actorWorld.actorValueHolder(for: key)
        else { return }
        runtime.damage(.stamina, by: amount, on: holder)
    }

    var equipment: (any EquipmentAccess)? {
        game.inventory.equipment
    }

    func magicInfluence(of key: ReferenceKey) -> ActorMagicInfluence {
        game.magic.influence(of: key)
    }

    func packageIgnoresCombat(_ key: ReferenceKey) -> Bool {
        game.packages.ignoresCombat(key)
    }

    func level(of key: ReferenceKey) -> Int? {
        guard
            let runtime = game.actorValues.runtime,
            let holder = game.actorWorld.actorValueHolder(for: key)
        else { return nil }
        return runtime.baseline(of: holder).level
    }

    func reaction(of observer: ReferenceKey, toward target: ReferenceKey) -> ActorReaction? {
        game.factions.reaction(of: observer, toward: target)
    }

    func enchantmentProfile(of item: FormID) -> ItemEnchantmentProfile? {
        game.magic.enchantmentProfile(of: item, on: .player)
    }

    func temperLevel(of item: FormID) -> Int32 {
        guard let runtime = game.inventory.runtime else { return 0 }
        return runtime.inventory.temperLevel(of: item, in: runtime.player)
    }

    func equippedItems(of key: ReferenceKey) -> [(item: FormID, temperLevel: Int32)] {
        guard
            let runtime = game.inventory.runtime,
            let equipment = game.inventory.equipment,
            let holder = key == .player ? runtime.player : game.streamer?.inventoryHolder(of: key)
        else { return [] }
        return equipment.equipped(on: holder).map {
            ($0, runtime.inventory.temperLevel(of: $0, in: holder))
        }
    }

    func hasReadiedSpell(in hand: SpellHand) -> Bool {
        game.magic.hasReadiedSpell(in: hand)
    }

    func playerCarriedItems() -> [FormID] {
        guard let runtime = game.inventory.runtime else { return [] }
        return runtime.inventory.inventory(of: runtime.player).stacks.map(\.item)
    }

    @discardableResult
    func addItem(_ item: FormID, count: Int32, to key: ReferenceKey) -> Bool {
        guard
            let runtime = game.inventory.runtime,
            let holder = game.streamer?.inventoryHolder(of: key)
        else { return false }
        return (try? runtime.inventory.add(item, count: count, to: holder)) != nil
    }

    @discardableResult
    func removeOneFromPlayer(_ item: FormID) -> Bool {
        guard let runtime = game.inventory.runtime else { return false }
        return (try? runtime.inventory.remove(item, count: 1, from: runtime.player)) != nil
    }

    @discardableResult
    func moveActor(_ key: ReferenceKey, to point: SIMD3<Float>) -> Bool {
        game.streamer?.moveActor(key, to: point) == .started
    }

    @discardableResult
    func moveActor(_ key: ReferenceKey, to point: SIMD3<Float>, gait: LocomotionGait?) -> Bool {
        game.streamer?.moveActor(key, to: point, gait: gait) == .started
    }

    func faceActor(_ key: ReferenceKey, toward point: SIMD3<Float>) {
        _ = game.streamer?.faceActor(key, towards: point)
    }

    func stopActor(_ key: ReferenceKey) {
        game.streamer?.stopActor(key)
    }

    func resumePackage(for key: ReferenceKey) {
        game.packages.resume(key)
    }

    /// True when the graph declared a home for the event, which is the graph's
    /// own answer rather than an assumption.
    @discardableResult
    func raisePlayerGraphEvent(_ name: String) -> Bool {
        guard let gameSession = game.gameSession else { return false }
        gameSession.locomotion.raise(name)
        return gameSession.locomotion.status.raisedEvents.contains(name)
    }

    func writePlayerGraphVariable(_ value: BehaviorVariableValue, named name: String) {
        game.gameSession?.locomotion.write(value, to: name)
    }

    func recordHealthHit(_ hit: CombatHitRecord, on key: ReferenceKey) {
        game.ragdoll.noteHit(hit, on: key)
    }

    /// A playback failure is logged by the engine and leaves the hit silent. The
    /// file loads off the main actor and is kept, so a repeated impact does not read it.
    func playImpact(_ impact: ResolvedMeleeImpact, at position: SIMD3<Float>) {
        showImpact(impact, at: position)
        guard
            let engine = game.gameSession?.worldAudio, engine.isRunning,
            let assets = game.audio.assets,
            let sounds = game.worldData?.soundStore,
            let sound = try? sounds.resolveAny(impact.sound),
            let path = sound.filePaths.first
        else { return }
        let request = AudioPlayRequest(
            name: path, category: sound.audioCategory ?? .footsteps, worldPosition: position
        )
        assets.request(path) { result in
            _ = try? engine.playPositional(asset: result.get(), request: request)
        }
    }

    func sweep(_ query: ShapeSweepQuery) -> ShapeSweepHit? {
        guard let streamer = game.streamer else { return nil }
        return ShapeSweeper.firstHit(
            query: query,
            shapes: streamer.staticCollisionCandidates(overlapping: query.bounds)
        )
    }

    func residentCells() -> Set<CellSceneLocation> {
        guard let streamer = game.streamer else { return [] }
        if let interior = streamer.interiorScene?.location {
            return [interior]
        }
        return Set(streamer.composition.cells.values.compactMap(\.location))
    }

    func spawn(_ reference: ReferenceSpawnState, in location: CellSceneLocation) -> ReferenceKey? {
        let key = game.worldState.allocateGeneratedKey()
        game.worldState.set(reference, for: key, in: location)
        return key
    }

    /// Dropping the whole delta, as `WorldItemRuntime.removeFromWorld` does,
    /// leaves nothing of a spawned object in the next save.
    var bodyTransients: CombatTransientCounts {
        CombatTransientCounts(
            activeRagdolls: game.ragdoll.runtime?.world.ragdollCount ?? 0,
            awakeBodies: game.streamer?.dynamicBodies.activeBodyCount ?? 0
        )
    }

    func trimBodyTransients(to limits: CombatTransientLimits) -> CombatTransientCounts {
        CombatTransientCounts(
            activeRagdolls: game.ragdoll.runtime?.trim(to: limits.activeRagdolls) ?? 0,
            awakeBodies: game.streamer?.dynamicBodies.sleepExcessBodies(over: limits.awakeBodies)
                ?? 0
        )
    }
}
