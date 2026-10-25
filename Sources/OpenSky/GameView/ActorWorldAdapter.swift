// App side of `ActorValueCoordinator`: builds its runtime from the provider,
// steps regeneration on the world delta, publishes the HUD meters, and answers
// which actors are resident. The rules live in the coordinator
// (docs/engine/coordinators.md).

import Foundation
import OpenSkyActors
import OpenSkyActorsInterface
import OpenSkyCells
import OpenSkyCombat
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMagic
import OpenSkyMenus
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyQuests
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyWorld
import OpenSkyWorldState
import simd

/// What `ActorWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
protocol ActorWorldHost: AnyObject {
    var actorValues: ActorValueCoordinator { get }
    var combat: CombatCoordinator { get }
    var hud: HUDCoordinator { get }
    var inventory: InventoryCoordinator { get }
    var journal: JournalCoordinator { get }
    var magic: MagicCoordinator { get }
    var gameSession: GameSession? { get }
    var streamer: CellStreamer? { get }
    var worldData: WorldDataStores? { get }
    var worldState: WorldStateStore { get }
    var mapWorld: MapWorldAdapter { get }
}

/// Answers `ActorValueWorld` and the resident-actor reads from the streamer.
final class ActorWorldAdapter {
    unowned let game: any ActorWorldHost
    /// Change gate in front of the HUD meter contract.
    private var meters = HUDMeterBinding()
    /// What the enemy health bar last showed; nil when it is hidden.
    private var publishedEnemy: HUDEnemyHealth?
    /// NPC_ base raw FormID -> resolved FULL, or nil when none resolves.
    private var baseNames: [LeveledActorRollKey: String?] = [:]
    /// Each reference's name, kept until a leveled roll is written or the strings load.
    private var referenceNames: (key: ReferenceNamesKey, names: [ReferenceKey: String?])?
    /// `combatActors()` and what it was built from. A death, a move, or a residency
    /// change advances one of the revisions, so the next read builds it again.
    private var actorList: (key: ActorListKey, actors: [CombatActorObservation])?

    init(game: any ActorWorldHost) {
        self.game = game
    }

    func wireActorValues(provider: WorldDataStores, gameSession: GameSession) {
        baseNames = [:]
        referenceNames = nil
        actorList = nil
        let coordinator = game.actorValues
        guard coordinator.runtime != nil else { return }
        let settings = provider.gameSettings
        // Chained after the Papyrus VM, so neither unhooks the other. The
        // renderer gates the delta, so a menu-paused frame regenerates nothing.
        gameSession.worldTick.register(.actorValues) { [weak coordinator] delta in
            coordinator?.advance(delta: delta)
        }
        gameSession.frameSteps.register(.actorValues) { [weak self, weak gameSession] _ in
            self?.publishHUDMeters(gameSession: gameSession)
        }
        gameSession.breath = PlayerBreath(settings: BreathSettings.resolve(store: settings))
        gameSession.worldTick.register(.breath) { [weak self, weak gameSession] delta in
            guard let gameSession else { return }
            self?.advanceBreath(delta: delta, gameSession: gameSession)
        }
    }

    /// Drowning costs health once the breath runs out; the `Water Breathing` actor value
    /// above 0 keeps the breath full.
    private func advanceBreath(delta: Float, gameSession: GameSession) {
        guard delta > 0 else { return }
        let runtime = game.actorValues.runtime
        let status = gameSession.locomotion.status
        let eyeZ = gameSession.walkController.feetPosition.z
            + gameSession.walkController.capsule.eyeHeight
        let submerged = gameSession.movementMode.isPlayerControlled
            && PlayerBreath.isSubmerged(eyeZ: eyeZ, waterSurface: status.waterSurfaceHeight)
        let waterBreathing = ActorValueIdentity.index(named: "Water Breathing")
            .flatMap { runtime?.value(at: $0, on: .player) }
            .map { $0 > 0 } ?? false
        let damage = gameSession.breath.advance(
            seconds: delta, submerged: submerged, waterBreathing: waterBreathing,
            maximumHealth: runtime?.maximums(of: .player).health ?? 0
        )
        if damage > 0 {
            game.combat.applyHealthDamage(damage, to: .player, attacker: nil)
        }
    }

    // MARK: - Resident actors

    /// Nil when nothing resident answers to `key`, such as an actor evicted
    /// mid-swing.
    func actorValueHolder(for key: ReferenceKey) -> ActorValueHolder? {
        if key == .player {
            return .player
        }
        guard let placement = game.streamer?.residentActorPlacement(key: key) else { return nil }
        return ActorValueHolder(
            key: key,
            subject: .actor(base: placement.base),
            cell: placement.cell
        )
    }

    /// Each pose is the NPC movement transform, then a stored override, then
    /// the placement.
    func combatActors() -> [CombatActorObservation] {
        guard let streamer = game.streamer else { return [] }
        let key = ActorListKey(
            streamer: ObjectIdentifier(streamer),
            poses: streamer.actorPoseRevision,
            deltas: game.worldState.deltaRevision,
            namesResolve: game.journal.strings != nil
        )
        if let actorList, actorList.key == key {
            return actorList.actors
        }
        let actors = streamer.residentActorEntries()
            .compactMap { observation(of: $0, in: streamer) }
        actorList = (key, actors)
        return actors
    }

    /// One resident actor from `combatActors()`, found by key in constant time.
    func combatActor(key: ReferenceKey) -> CombatActorObservation? {
        guard let streamer = game.streamer, let entry = streamer.residentActorEntry(key: key)
        else { return nil }
        return observation(of: entry, in: streamer)
    }

    private func observation(
        of entry: RuntimeReferenceEntry, in streamer: CellStreamer
    ) -> CombatActorObservation? {
        guard let actor = entry.placedActor else { return nil }
        let worldState = game.worldState
        let moved = streamer.npcTransform(for: entry.key)
            ?? worldState.component(ReferenceTransformOverride.self, for: entry.key)
        return CombatActorObservation(
            key: entry.key,
            feet: moved?.position ?? actor.placement.position,
            facing: moved?.rotation.z ?? actor.placement.rotation.z,
            scale: actor.scale,
            isDead: worldState.component(ActorDeathState.self, for: entry.key)?.isDead
                ?? false,
            label: displayName(of: entry.key, base: actor.base).map(ActorLabel.init)
                ?? ActorLabel(key: entry.key, base: actor.base)
        )
    }

    /// The FULL name of the actor `key` of `base` after template inheritance, its
    /// leveled template picked by its own roll, as the crosshair shows it.
    func displayName(of key: ReferenceKey, base: FormID) -> String? {
        let namesKey = ReferenceNamesKey(
            rolls: game.worldState.revision(of: [.leveledRoll]),
            namesResolve: game.journal.strings != nil
        )
        if referenceNames?.key != namesKey {
            referenceNames = (namesKey, [:])
        }
        if let cached = referenceNames?.names[key] {
            return cached
        }
        let name = resolveDisplayName(of: key, base: base)
        referenceNames?.names[key] = .some(name)
        return name
    }

    private func resolveDisplayName(of key: ReferenceKey, base: FormID) -> String? {
        guard
            let templates = game.worldData?
                .actorValueBaselines?.resolver?.templates,
            let strings = game.journal.strings
        else { return nil }
        let roll = game.worldState.leveledRoll(of: key, base: base, with: templates.leveling)
        let rollKey = LeveledActorRollKey(base: base, roll: roll)
        if let cached = baseNames[rollKey] {
            return cached
        }
        let name = (try? templates.rolling(roll).resolveName(base: base))
            .flatMap { strings.resolve($0.value) }
            .flatMap { $0.isEmpty ? nil : $0 }
        baseNames[rollKey] = .some(name)
        return name
    }

    private func publishHUDMeters(gameSession: GameSession?) {
        guard let gameSession, game.hud.isLoaded, let runtime = game.actorValues.runtime else {
            return
        }
        let meters = meters.publishing(runtime.hudMeters(for: .player))
        let enemy = engagedEnemyHealth(runtime: runtime, gameSession: gameSession)
        let enemyChanged = enemy != publishedEnemy
        guard meters != nil || enemyChanged else { return }
        publishedEnemy = enemy
        do {
            try gameSession.renderer.updateSWFRuntime { runtime in
                if let meters {
                    HUDMovieBridge.setMeters(meters, runtime: runtime)
                }
                if enemyChanged {
                    HUDMovieBridge.setEnemyHealth(enemy, runtime: runtime)
                }
            }
        } catch {
            Self.logger.error(
                "[ERROR] HUD meters not published: \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func engagedEnemyHealth(
        runtime: ActorValueRuntime, gameSession: GameSession
    ) -> HUDEnemyHealth? {
        guard
            let actor = game.combat.engagedEnemy(playerFeet: gameSession.freeFlyCamera.position),
            let holder = actorValueHolder(for: actor.key)
        else { return nil }
        let name = game.streamer?.residentActorPlacement(key: actor.key)
            .flatMap { displayName(of: actor.key, base: $0.base) } ?? ""
        return HUDEnemyHealth(name: name, health: runtime.hudMeters(for: holder).health)
    }

    private static let logger = EngineLogger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "ActorValues"
    )
}

extension ActorWorldAdapter: ActorValueWorld {
    func regeneratingHolders() -> [ActorValueHolder] {
        var holders: [ActorValueHolder] = [.player]
        guard let streamer = game.streamer else { return holders }
        for entry in streamer.residentActorEntries() {
            guard let actor = entry.placedActor else { continue }
            holders.append(ActorValueHolder(
                key: entry.key,
                subject: .actor(base: actor.base),
                cell: streamer.cellLocation(of: entry.key)
            ))
        }
        return holders
    }

    func nearestActorValueHolder() -> ActorValueHolder? {
        guard
            let streamer = game.streamer,
            let gameSession = game.gameSession,
            let entry = streamer.nearestActorEntry(to: gameSession.freeFlyCamera.position),
            let actor = entry.placedActor
        else { return nil }
        return ActorValueHolder(
            key: entry.key,
            subject: .actor(base: actor.base),
            cell: streamer.cellLocation(of: entry.key)
        )
    }

    func isCasting(_ key: ReferenceKey) -> Bool {
        game.magic.caster?.isCasting(key) == true
    }

    func isInCombat(_ key: ReferenceKey) -> Bool {
        guard let loop = game.combat.loop else { return false }
        return key == .player ? loop.isPlayerInCombat : loop.activity(of: key) != .notFighting
    }

    /// Standing still with the sprint key held costs nothing.
    func playerSprintLoad() -> Float? {
        guard
            let status = game.gameSession?.locomotion.status,
            status.gait == .sprint,
            simd_length(status.horizontalVelocity) > 1
        else { return nil }
        guard let equipment = game.inventory.equipment, let items = game.combat.items
        else { return 0 }
        return equipment.equipped(on: .player).reduce(Float(0)) {
            $0 + (items.definition($1)?.weight ?? 0)
        }
    }

    func setPlayerSprintAllowed(_ allowed: Bool) {
        game.gameSession?.locomotion.isSprintAllowed = allowed
    }

    func playerCarriedWeight() -> Float? {
        game.inventory.runtime == nil ? nil : game.inventory.playerCarriedWeight
    }

    func setPlayerOverencumbered(_ overencumbered: Bool) {
        game.gameSession?.locomotion.isRunAllowed = !overencumbered
        guard overencumbered else { return }
        game.hud.showNotification(
            game.mapWorld.text(game.mapWorld.records?.menuTexts["sOverEncumbered"])
                ?? "You are carrying too much to be able to run."
        )
    }
}

/// The inputs of `ActorWorldAdapter`'s per-reference names.
private struct ReferenceNamesKey: Equatable {
    let rolls: UInt64
    let namesResolve: Bool
}

/// The inputs of one `ActorWorldAdapter.combatActors()` list.
private struct ActorListKey: Hashable {
    let streamer: ObjectIdentifier
    let poses: UInt64
    let deltas: UInt64
    let namesResolve: Bool
}
