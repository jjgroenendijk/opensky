// App side of `ActorValueCoordinator`: builds its runtime from the provider,
// steps regeneration on the world delta, publishes the HUD meters, and answers
// which actors are resident. The rules live in the coordinator
// (docs/engine/coordinators.md).

import Foundation
public import OpenSkyActors
import OpenSkyActorsInterface
import OpenSkyCells
public import OpenSkyCombatInterface
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyQuestsInterface
import OpenSkyRenderCore
import OpenSkyRendering
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `ActorWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
public protocol ActorWorldHost: AnyObject, SendableMetatype {
    var actorValues: any ActorValuePort { get }
    var combat: any CombatPort { get }
    var hud: any HUDPort { get }
    var inventory: any InventoryPort { get }
    var journal: any JournalPort { get }
    var magic: any MagicPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var streamer: any CellStreamerPort { get }
    var actorRecords: (any ActorRecordsPort)? { get }
    var worldState: any WorldStateStorePort { get }
    var mapWorld: any MapWorldPort { get }
    var mounts: any MountPort { get }
}

/// Answers `ActorValueWorld` and the resident-actor reads from the streamer.
public final class ActorWorldAdapter {
    public let game: any ActorWorldHost
    let names: ActorDisplayNames
    let breathStep: ActorBreathStep
    /// `combatActors()` and what it was built from. A death, a move, or a residency
    /// change advances one of the revisions, so the next read builds it again.
    var actorList: (key: ActorListKey, actors: [CombatActorObservation])?

    public init(game: any ActorWorldHost) {
        self.game = game
        names = ActorDisplayNames(game: game)
        breathStep = ActorBreathStep(game: game)
    }

    // MARK: - Resident actors

    /// Nil when nothing resident answers to `key`, such as an actor evicted
    /// mid-swing.
    public func actorValueHolder(for key: ReferenceKey) -> ActorValueHolder? {
        if key == .player {
            return .player
        }
        guard let placement = game.streamer.residentActorPlacement(key: key) else { return nil }
        return ActorValueHolder(
            key: key,
            subject: .actor(base: placement.base),
            cell: placement.cell
        )
    }

    /// Each pose is the NPC movement transform, then a stored override, then
    /// the placement.
    public func combatActors() -> [CombatActorObservation] {
        let streamer = game.streamer
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
    public func combatActor(key: ReferenceKey) -> CombatActorObservation? {
        let streamer = game.streamer
        guard let entry = streamer.residentActorEntry(key: key)
        else { return nil }
        return observation(of: entry, in: streamer)
    }

    private func observation(
        of entry: RuntimeReferenceEntry, in streamer: any CellStreamerPort
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
    public func displayName(of key: ReferenceKey, base: FormID) -> String? {
        names.displayName(of: key, base: base)
    }
}

extension ActorWorldAdapter: ActorValueWorld {
    public func regeneratingHolders() -> [ActorValueHolder] {
        var holders: [ActorValueHolder] = [.player]
        let streamer = game.streamer
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

    public func nearestActorValueHolder() -> ActorValueHolder? {
        let streamer = game.streamer
        guard
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

    public func isCasting(_ key: ReferenceKey) -> Bool {
        motion.isCasting(key)
    }

    public func isInCombat(_ key: ReferenceKey) -> Bool {
        motion.isInCombat(key)
    }

    public func playerSprintLoad() -> Float? {
        motion.playerSprintLoad()
    }

    public func setPlayerSprintAllowed(_ allowed: Bool) {
        motion.setPlayerSprintAllowed(allowed)
    }

    public func riddenHorse() -> ActorValueHolder? {
        guard let drive = game.mounts.drive, drive.kind == .horse else { return nil }
        return actorValueHolder(for: drive.mount)
    }

    public func isRiddenHorseSprinting() -> Bool {
        motion.isRiddenHorseSprinting()
    }

    public func setRiddenHorseSprintAllowed(_ allowed: Bool) {
        game.mounts.allowRiddenHorseSprint(allowed)
    }

    public func playerCarriedWeight() -> Float? {
        game.inventory.runtime == nil ? nil : game.inventory.armourWeights.playerCarriedWeight
    }

    public func setPlayerOverencumbered(_ overencumbered: Bool) {
        motion.setPlayerOverencumbered(overencumbered)
    }
}

/// The inputs of `ActorWorldAdapter`'s per-reference names.
struct ReferenceNamesKey: Hashable {
    let rolls: UInt64
    let namesResolve: Bool
}

/// The inputs of one `ActorWorldAdapter.combatActors()` list.
struct ActorListKey: Hashable {
    let streamer: ObjectIdentifier
    let poses: UInt64
    let deltas: UInt64
    let namesResolve: Bool
}

extension ActorWorldAdapter: ActorWorldPort {}

/// The display-name caches of `ActorWorldAdapter`, one per session.
final class ActorDisplayNames {
    let game: any ActorWorldHost
    /// NPC_ base raw FormID -> resolved FULL, or nil when none resolves.
    var baseNames: [LeveledActorRollKey: String?] = [:]
    /// Each reference's name, kept until a leveled roll is written or the strings load.
    var referenceNames: (key: ReferenceNamesKey, names: [ReferenceKey: String?])?

    init(game: any ActorWorldHost) {
        self.game = game
    }

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

    func resolveDisplayName(of key: ReferenceKey, base: FormID) -> String? {
        guard
            let templates = game.actorRecords?
                .actorValueBaselines?.resolver?.templates,
            let strings = game.journal.strings
        else { return nil }
        let roll = game.worldState.leveledRoll(of: key, base: base, with: templates.leveling)
        let rollKey = LeveledActorRollKey(base: base, roll: roll)
        if let cached = baseNames[rollKey] {
            return cached
        }
        let name = attempt { try templates.rolling(roll).resolveName(base: base) }
            .flatMap { strings.resolve($0.value) }
            .flatMap { $0.isEmpty ? nil : $0 }
        baseNames[rollKey] = .some(name)
        return name
    }
}

/// The player's combat, casting, sprint, and load reads of `ActorWorldAdapter`.
struct ActorPlayerMotion {
    let game: any ActorWorldHost

    func isCasting(_ key: ReferenceKey) -> Bool {
        game.magic.caster?.isCasting(key) == true
    }

    func isInCombat(_ key: ReferenceKey) -> Bool {
        guard let loop = game.combat.loop else { return false }
        return key == .player ? loop.isPlayerInCombat : loop.activity(of: key) != .notFighting
    }

    /// Standing still with the sprint key held costs nothing. A rider's horse sprints.
    func playerSprintLoad() -> Float? {
        guard
            !game.mounts.isActive,
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

    func isRiddenHorseSprinting() -> Bool {
        guard let drive = game.mounts.drive, drive.kind == .horse else { return false }
        return drive.motion.isSprinting && drive.motion.isMoving
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

extension ActorWorldAdapter {
    var motion: ActorPlayerMotion {
        ActorPlayerMotion(game: game)
    }

    var hudMeters: ActorHUDMeters {
        ActorHUDMeters(game: game, world: self)
    }
}

/// The player's breath under water, for `ActorWorldAdapter`.
struct ActorBreathStep {
    let game: any ActorWorldHost

    /// Drowning costs health once the breath runs out; the `Water Breathing` actor value
    /// above 0 keeps the breath full.
    func advanceBreath(delta: Float, gameSession: GameSession) {
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
}

/// The HUD's health, magicka, and stamina meters, for `ActorWorldAdapter`.
struct ActorHUDMeters {
    let game: any ActorWorldHost
    let world: any ActorValueWorld & ActorWorldPort

    func publishHUDMeters(gameSession: GameSession?) {
        guard let gameSession, game.hud.isLoaded, let runtime = game.actorValues.runtime else {
            return
        }
        var meters = runtime.fractions(of: .player)
        if let horse = world.riddenHorse() {
            meters.stamina = runtime.fractions(of: horse).stamina
        }
        let enemy = game.hud.shows(.enemyHealth)
            ? engagedEnemyHealth(runtime: runtime, gameSession: gameSession) : nil
        game.hud.publishMeters(meters, enemy: enemy)
    }

    private func engagedEnemyHealth(
        runtime: any ActorValueRuntimePort, gameSession: GameSession
    ) -> HUDEnemyHealth? {
        guard
            let actor = game.combat.engagedEnemy(playerFeet: gameSession.freeFlyCamera.position),
            let holder = world.actorValueHolder(for: actor.key)
        else { return nil }
        let name = game.streamer.residentActorPlacement(key: actor.key)
            .flatMap { world.displayName(of: actor.key, base: $0.base) } ?? ""
        return HUDEnemyHealth(name: name, health: runtime.fractions(of: holder).health)
    }
}
