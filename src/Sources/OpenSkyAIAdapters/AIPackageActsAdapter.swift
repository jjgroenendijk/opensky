import OpenSkyActorPresentation
import OpenSkyActorsInterface
public import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyDialogueInterface
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
public import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `AIPackageActsAdapter` reads from the session.
@MainActor
public protocol AIPackageActsHost: AnyObject, SendableMetatype {
    var actorGraphWorld: any ActorGraphWorldPort { get }
    var actorWorld: any ActorWorldPort { get }
    var combat: any CombatPort { get }
    var dialogue: any DialoguePort { get }
    var dialogueMenu: any DialogueMenuPort { get }
    var headTracking: any HeadTrackingPort { get }
    var inventory: any InventoryPort { get }
    var packages: any PackagePort { get }
    var scripts: any ScriptPort { get }
    var storyWorld: any StoryWorldPort { get }
    var streamer: any CellStreamerPort { get }
    var aiRecords: (any AIRecordsPort)? { get }
}

/// Part of `AIWorldAdapter`, over its own narrow host.
public struct AIPackageActsAdapter {
    public let game: any AIPackageActsHost
    let packageMoves: AIPackageMovesAdapter
    public let navigation: AINavigationAdapter
}

extension AIPackageActsAdapter {
    /// How far LockDoors and UnlockDoors reach when the package place has no radius.
    public static let doorReach: Float = 2048
    /// How far a find looks when its place has no radius.
    public static let findReach: Float = 2048

    public func stopPackageActor(_ actor: ReferenceKey) {
        _ = navigation.stopActor(actor)
    }

    public func packageAction(_ action: PackageAction, actor: ReferenceKey) -> PackageActionResult {
        switch action {
        case let .setDoorsLocked(locked, center, radius):
            references.setDoorsLocked(locked, around: center, radius: radius, owner: actor)
        case let .find(selector, center, radius):
            .found(references.find(selector, around: center, radius: radius))
        case let .activate(target):
            activate(target, by: actor)
        case let .pickUp(item):
            pickUp(item, by: actor)
        case let .say(topic, target):
            say(topic, speaker: actor, to: target)
        case .forceGreet:
            greet(actor)
        case let .talk(target):
            look(at: target, from: actor)
        case let .warn(intruder, _):
            warn(intruder, from: actor)
        case .standDown:
            standDown(actor)
        default:
            combatAction(action, actor: actor)
        }
    }

    private func combatAction(_ action: PackageAction, actor: ReferenceKey) -> PackageActionResult {
        guard let bridge = game.scripts.bridge else { return .failed }
        switch action {
        case let .attack(target?, startsCombat: true):
            return bridge.startActorCombat(actor, target: target) ? .done : .failed
        case let .cast(selector, target):
            guard let spell = selector.flatMap(references.selectedForm) else { return .failed }
            return bridge.castSpell(spell, from: actor, at: target, blame: nil) ? .done : .failed
        case let .shout(selector, target):
            guard let spell = references.shoutSpell(for: selector) else { return .failed }
            return bridge.castSpell(spell, from: actor, at: target, blame: nil) ? .done : .failed
        default:
            return .failed
        }
    }

    /// `PTDA` object type codes the vanilla templates use, and the test for each.
    public enum PackageObjectType: UInt32 {
        case furniture = 10
        case weapon = 11
        case food = 15
        case bed = 26
        case chair = 27
    }

    public func activate(_ target: ReferenceKey, by actor: ReferenceKey) -> PackageActionResult {
        guard let bridge = game.scripts.bridge else { return .failed }
        _ = bridge.activate(target, by: actor, togglesOpen: true)
        return .done
    }

    /// The item moves into the actor's inventory and leaves the world.
    public func pickUp(_ item: ReferenceKey, by actor: ReferenceKey) -> PackageActionResult {
        guard
            let bridge = game.scripts.bridge,
            let entry = game.streamer.referenceEntry(key: item),
            let reference = entry.placedReference,
            game.inventory.scriptAddItem(
                reference.base, count: max(1, reference.itemCount ?? 1), to: actor
            )
        else { return .failed }
        _ = bridge.write(ReferenceDeletionState.deleted.erased, for: item)
        return .done
    }

    /// One line of the topic, chosen as a scene chooses it, voiced and subtitled.
    public func say(
        _ topic: FormID?, speaker: ReferenceKey, to target: ReferenceKey?
    ) -> PackageActionResult {
        guard
            let topic, let runtime = game.dialogue.runtime,
            let offer = runtime.topics(linked: [topic], speaker: speaker).offers.first,
            attempt({ try runtime.choose(offer.info, speaker: speaker) }) != nil,
            let info = runtime.dialogue.info(offer.info)
        else { return .failed }
        let seconds = game.storyWorld.lineDuration(of: info, speaker: speaker)
            ?? PackageActionResult.unvoicedLineSeconds
        game.storyWorld.speak(
            info: offer.info, speaker: speaker, lookAt: target, seconds: seconds
        )
        return .lasts(seconds: seconds)
    }

    /// The conversation opens with the actor's greeting. The package's own topic is not
    /// forced: the greeting is picked as when the player talks to the actor. An actor waits
    /// `fAIForceGreetingTimer` before it may force greet again.
    public func greet(_ actor: ReferenceKey) -> PackageActionResult {
        guard game.dialogue.claimForceGreet(speaker: actor, now: game.storyWorld.sceneSeconds)
        else { return .failed }
        game.dialogueMenu.begin(with: actor)
        return game.dialogueMenu.isOpen ? .done : .failed
    }

    /// DialogueActivate: OpenSky has no conversations between two NPCs, so the actor
    /// turns its head to the target.
    public func look(at target: ReferenceKey, from actor: ReferenceKey) -> PackageActionResult {
        let seconds = PackageActionResult.lookSeconds
        game.headTracking.setLookTarget(target, for: actor, seconds: seconds)
        return .lasts(seconds: seconds)
    }

    /// The graph events that draw and sheathe the weapon.
    public static let drawWeaponEvent = "WeapEquip"
    public static let sheatheWeaponEvent = "Unequip"

    /// An actor whose combat override package runs is held out of the fight, so it
    /// still counts as fighting while it stays hostile.
    public func packageSituations(of actors: [ReferenceKey]) -> [ReferenceKey: PackageSituation] {
        let loop = game.combat.loop
        let observations = game.actorWorld.combatActors().map { actor in
            let engaged = loop?.phase(of: actor.key)?.isEngaged == true
            let held = game.packages.runtime?.source(for: actor.key) == .situation(.combat)
                && game.combat.combatHostility(of: actor.key) == .hostile
            return PackageSituationObservation(
                key: actor.key, position: actor.feet, isDead: actor.isDead,
                isFighting: !actor.isDead && (engaged || held)
            )
        }
        return PackageSituationScan.situations(of: actors, observations: observations)
    }

    /// The guard draws its weapon and says a trespass line, when the load order has one
    /// it may say now. Without one the warning still counts.
    public func warn(_ intruder: ReferenceKey, from guardKey: ReferenceKey) -> PackageActionResult {
        _ = game.actorGraphWorld.graphs.raise(Self.drawWeaponEvent, on: guardKey)
        guard
            let seconds = game.storyWorld.sayTopic("TRES", speaker: guardKey, lookAt: intruder)
        else { return .done }
        return .lasts(seconds: seconds)
    }

    public func standDown(_ guardKey: ReferenceKey) -> PackageActionResult {
        _ = game.actorGraphWorld.graphs.raise(Self.sheatheWeaponEvent, on: guardKey)
        return .done
    }
}
