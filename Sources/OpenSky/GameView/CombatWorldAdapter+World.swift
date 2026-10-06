// The app's answers to `CombatWorld`: each one a plain read of, or a write to,
// a session system the view controller owns.

import OpenSkyActors
import OpenSkyActorsInterface
import OpenSkyAudio
import OpenSkyBehavior
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyCrime
import OpenSkyFactions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMagic
import OpenSkyMagicInterface
import OpenSkyPerception
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyProgression
import OpenSkyProgressionInterface
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyWorld
import OpenSkyWorldState
import simd

extension CombatWorldAdapter: CombatWorld {
    /// Every landed blow passes here, so assault is noticed in one place.
    @discardableResult
    func reportScriptHit(_ hit: ScriptHitEvent) -> Int {
        game.crime.reportAssault(
            on: hit.target,
            wasHostile: hostility(of: hit.target) == .hostile,
            aggressor: hit.aggressor
        )
        return game.scripts.runtime?.queueOnHit(hit) ?? 0
    }

    @discardableResult
    func reportSkillUse(_ use: SkillUseEvent) -> Float {
        game.progression.reportSkillUse(use)
    }

    @discardableResult
    func applySpellHit(_ hit: SpellHit) -> SpellHitReport {
        game.magic.applySpellHit(hit)
    }

    @discardableResult
    func applyWeaponEnchantment(_ hit: WeaponEnchantmentHit) -> WeaponEnchantmentReport? {
        game.magic.applyWeaponEnchantment(hit)
    }

    var playerAttacker: MeleeAttacker? {
        guard let renderer = game.renderer else { return nil }
        return MeleeAttacker(
            key: .player,
            feet: renderer.walkController.feetPosition,
            capsule: renderer.walkController.capsule,
            facing: renderer.freeFlyCamera.yaw
        )
    }

    var playerShooter: ProjectileShooter? {
        guard let renderer = game.renderer else { return nil }
        return ProjectileShooter(
            key: .player,
            origin: renderer.freeFlyCamera.position,
            aim: renderer.freeFlyCamera.forward,
            isFirstPerson: renderer.movementMode != .thirdPerson,
            location: game.streamer?.currentCellLocation
        )
    }

    func residentActors() -> [CombatActorObservation] {
        game.actorWorld.combatActors()
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

    /// ZNAM after template inheritance, read through the load-order CSTY store.
    func combatStyle(of key: ReferenceKey) -> CombatStyleTuning? {
        guard
            case let .actor(base)? = game.actorWorld.actorValueHolder(for: key)?.subject,
            let resolver = (game.worldData as? ActorValueDataProviding)?.actorValueBaselines?
                .resolver,
            let link = try? resolver.templates.resolveCombatStyle(base: base).value,
            let style = (game.worldData as? PresentationDataProviding)?.presentationRecords?
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

    var equipment: (any EquipmentAccess)? {
        game.inventory.equipment
    }

    func enchantmentProfile(of item: FormID) -> ItemEnchantmentProfile? {
        game.magic.enchantmentProfile(of: item)
    }

    func hasReadiedSpell(in hand: SpellHand) -> Bool {
        game.magic.hasReadiedSpell(in: hand)
    }

    func playerCarriedItems() -> [FormID] {
        guard let runtime = game.inventory.runtime else { return [] }
        return runtime.inventory.inventory(of: runtime.player).stacks.map(\.item)
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
        guard let renderer = game.renderer else { return false }
        renderer.locomotion.raise(name)
        return renderer.locomotion.status.raisedEvents.contains(name)
    }

    func writePlayerGraphVariable(_ value: BehaviorVariableValue, named name: String) {
        game.renderer?.locomotion.write(value, to: name)
    }

    /// A playback failure is logged by the engine and leaves the hit silent. The
    /// file loads off the main actor and is kept, so a repeated impact does not read it.
    func playImpact(_ impact: ResolvedMeleeImpact, at position: SIMD3<Float>) {
        guard
            let engine = game.renderer?.worldAudio, engine.isRunning,
            let assets = game.audio.assets,
            let sounds = (game.worldData as? AudioDataProviding)?.soundStore,
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

    func setCombatMusicActive(_ active: Bool) {
        game.audio.musicDirector?.setCombatActive(active)
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
    func resetReference(_ key: ReferenceKey) {
        game.worldState.reset(key)
    }

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

    func resetRagdolls() {
        game.ragdoll.runtime?.reset()
    }
}
