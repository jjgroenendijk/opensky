import OpenSkyActorPresentation
public import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyAudio
import OpenSkyBehavior
import OpenSkyCells
public import OpenSkyCombat
public import OpenSkyCombatInterface
public import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyDialogueInterface
import OpenSkyFactionsInterface
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyNavigation
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyPlayer
public import OpenSkyProgressionInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `CombatActorFactsAdapter` reads from the session.
@MainActor
public protocol CombatActorFactsHost: AnyObject, SendableMetatype {
    var actorValues: any ActorValuePort { get }
    var actorWorld: any ActorWorldPort { get }
    var factions: any FactionPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var perception: any PerceptionPort { get }
    var perks: any PerkPort { get }
    var ragdoll: any RagdollPort { get }
    var streamer: any CellStreamerPort { get }
    var combatRecords: (any CombatRecordsPort)? { get }
    var worldState: any WorldStateStorePort { get }
}

/// Part of `CombatWorldAdapter`, over its own narrow host.
public struct CombatActorFactsAdapter {
    public let game: any CombatActorFactsHost
}

extension CombatActorFactsAdapter {
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
            location: game.streamer.currentCellLocation
        )
    }

    public func residentActors() -> [CombatActorObservation] {
        game.actorWorld.combatActors()
    }

    public func residentActor(key: ReferenceKey) -> CombatActorObservation? {
        game.actorWorld.combatActor(key: key)
    }

    /// The nearest resident actor: the same selector the actor-value controls use.
    public func selectedActor() -> ReferenceKey? {
        game.actorWorld.nearestActorValueHolder()?.key
    }

    public func hostility(of key: ReferenceKey) -> ActorHostility {
        game.factions.hostility(of: key)
    }

    @discardableResult
    public func setHostility(_ hostility: ActorHostility, on key: ReferenceKey) -> Bool {
        game.factions.setHostility(hostility, on: key)
    }

    public func awareness(
        of observer: ReferenceKey,
        toward target: ReferenceKey
    ) -> CombatAwareness {
        guard let runtime = game.perception.runtime else { return .unaware }
        let pair = runtime.state(observer: observer, target: target)
        return CombatAwareness(state: pair.state, lastKnownPosition: pair.lastKnownPosition)
    }

    public func actorValues(of key: ReferenceKey) -> ((Int32) -> Float?)? {
        guard
            let runtime = game.actorValues.runtime,
            let holder = game.actorWorld.actorValueHolder(for: key)
        else { return nil }
        return { runtime.value(at: $0, on: holder) }
    }

    public func perkMultiplier(at entryPoint: PerkEntryPoint, on key: ReferenceKey) -> Float {
        game.perks.multiplier(at: entryPoint, on: key)
    }

    public func perkModified(
        _ value: Float,
        at entryPoint: PerkEntryPoint,
        on key: ReferenceKey,
        given conditions: (subjects: PerkEvaluationSubjects, seams: ConditionContext)
    ) -> Float {
        game.perks.modified(
            value,
            at: entryPoint,
            on: key,
            subjects: { _ in conditions.subjects },
            seams: conditions.seams
        )
    }

    public func perkChoices(
        at entryPoint: PerkEntryPoint,
        on key: ReferenceKey,
        subjects: PerkEvaluationSubjects,
        seams: ConditionContext
    ) -> [PerkEntryPointChoice] {
        game.perks.choices(at: entryPoint, on: key, subjects: { _ in subjects }, seams: seams)
    }

    var isInInterior: Bool {
        game.streamer.interiorScene != nil
    }

    /// ZNAM after template inheritance, read through the load-order CSTY store.
    public func combatStyle(of key: ReferenceKey) -> CombatStyleTuning? {
        styleReader.combatStyle(of: key)
    }

    public func actorName(of key: ReferenceKey) -> String? {
        guard
            let holder = game.actorWorld.actorValueHolder(for: key),
            case let .actor(base) = holder.subject
        else { return nil }
        return game.actorWorld.displayName(of: key, base: base)
    }

    public func health(of key: ReferenceKey) -> (current: Float, maximum: Float)? {
        guard
            let runtime = game.actorValues.runtime,
            let holder = game.actorWorld.actorValueHolder(for: key)
        else { return nil }
        return (runtime.current(of: holder).health, runtime.maximums(of: holder).health)
    }

    @discardableResult
    public func damageHealth(by amount: Float, of key: ReferenceKey) -> Bool {
        guard
            let runtime = game.actorValues.runtime,
            let holder = game.actorWorld.actorValueHolder(for: key)
        else { return false }
        let kept = key == .player ? game.ragdoll.playerDeath.incomingDamageMult : 1
        runtime.damage(.health, by: amount * kept, on: holder)
        return true
    }

    public func ownsPerk(editorID: String, on key: ReferenceKey) -> Bool {
        guard
            let perk = game.perks.runtime?.perks.perk(editorID: editorID),
            let owned = game.perks.ownership(of: key)
        else { return false }
        return owned.contains(ReferenceKey(resolved: perk.id))
    }

    public func damageStamina(by amount: Float, of key: ReferenceKey) {
        guard
            let runtime = game.actorValues.runtime,
            let holder = game.actorWorld.actorValueHolder(for: key)
        else { return }
        runtime.damage(.stamina, by: amount, on: holder)
    }

    public func pauseBowZoomStamina() {
        guard let runtime = game.actorValues.runtime else { return }
        runtime.pauseRegeneration(
            .stamina, on: .player, for: runtime.regeneration.bowZoomStaminaDelay
        )
    }

    public func level(of key: ReferenceKey) -> Int? {
        guard
            let runtime = game.actorValues.runtime,
            let holder = game.actorWorld.actorValueHolder(for: key)
        else { return nil }
        return runtime.baseline(of: holder).level
    }

    public func reaction(of observer: ReferenceKey, toward target: ReferenceKey) -> ActorReaction? {
        game.factions.reaction(of: observer, toward: target)
    }
}

extension CombatActorFactsAdapter {
    var styleReader: CombatStyleReader {
        CombatStyleReader(game: game)
    }
}

struct CombatStyleReader {
    let game: any CombatActorFactsHost

    /// ZNAM after template inheritance, read through the load-order CSTY store.
    func combatStyle(of key: ReferenceKey) -> CombatStyleTuning? {
        guard
            case let .actor(base)? = game.actorWorld.actorValueHolder(for: key)?.subject,
            let resolver = game.combatRecords?.actorValueBaselines?
                .resolver,
            let link = attempt({ try resolver.templates
                    .rolling(game.worldState.leveledRoll(
                        of: key, base: base, with: resolver.templates.leveling
                    ))
                    .resolveCombatStyle(base: base).value }),
            let style = game.combatRecords?.presentationRecords?
                .combatStyles.resolve(link, fromPlugin: resolver.pluginName)
        else { return nil }
        return CombatStyleTuning(style: style.record)
    }
}

extension CombatActorFactsAdapter: CombatPerkReads {}
