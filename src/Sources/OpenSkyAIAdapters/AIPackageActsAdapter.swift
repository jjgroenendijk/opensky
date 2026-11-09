import OpenSkyActorPresentation
import OpenSkyActorsInterface
public import OpenSkyAIPackages
public import OpenSkyCells
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
public import OpenSkyWorldState
import simd

/// What `AIPackageActsAdapter` reads from the session.
@MainActor
public protocol AIPackageActsHost: AnyObject {
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
    var worldData: WorldDataStores? { get }
}

/// Part of `AIWorldAdapter`, over its own narrow host.
public struct AIPackageActsAdapter {
    public let game: any AIPackageActsHost
    public let packageMoves: AIPackageMovesAdapter
    public let navigation: AINavigationAdapter
}

extension AIPackageActsAdapter {
    /// How far LockDoors and UnlockDoors reach when the package place has no radius.
    public static let doorReach: Float = 2048
    /// How far a find looks when its place has no radius.
    public static let findReach: Float = 2048

    public func packageReference(
        _ target: Package.Target, actor: ReferenceKey, aliasQuest: FormID?
    ) -> ReferenceKey? {
        if let key = packageMoves.packageTargetKey(target, aliasQuest: aliasQuest) {
            return key
        }
        switch target.kind {
        case .linkedReference:
            let entry = game.streamer.referenceEntry(key: actor)
            let links = entry?.placedReference?.linkedReferences
                ?? entry?.placedActor?.details.linkedReferences ?? []
            let keyword = FormID(target.value).nonNull
            return links.first { $0.keyword == keyword }.flatMap { resolveForm($0.ref) }
        case .objectID:
            let position = packageMoves.packageActorPosition(actor) ?? .zero
            return nearest(to: position, within: .infinity) {
                ConditionFunctions.baseForm(of: $0) == FormID(target.value)
            }
        default:
            return nil
        }
    }

    public func stopPackageActor(_ actor: ReferenceKey) {
        _ = navigation.stopActor(actor)
    }

    public func packageAction(_ action: PackageAction, actor: ReferenceKey) -> PackageActionResult {
        switch action {
        case let .setDoorsLocked(locked, center, radius):
            setDoorsLocked(locked, around: center, radius: radius, owner: actor)
        case let .find(selector, center, radius):
            .found(find(selector, around: center, radius: radius))
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
            guard let spell = selector.flatMap(selectedForm) else { return .failed }
            return bridge.castSpell(spell, from: actor, at: target, blame: nil) ? .done : .failed
        case let .shout(selector, target):
            guard let spell = selector.flatMap(shoutSpell) else { return .failed }
            return bridge.castSpell(spell, from: actor, at: target, blame: nil) ? .done : .failed
        default:
            return .failed
        }
    }

    private func resolveForm(_ formID: FormID) -> ReferenceKey? {
        game.scripts.bridge?.formIDResolver.flatMap { ReferenceKey.resolve(formID, using: $0) }
    }

    /// The form a selector names by its object ID, such as a spell.
    private func selectedForm(_ selector: Package.Target) -> ReferenceKey? {
        guard selector.kind == .objectID || selector.kind == .specificReference else {
            return nil
        }
        return resolveForm(FormID(selector.value))
    }

    /// The spell of the first word of the shout a selector names.
    private func shoutSpell(_ selector: Package.Target) -> ReferenceKey? {
        guard
            let key = selectedForm(selector),
            let shouts = game.worldData?.shoutStore,
            let shout = shouts.shouts.values.first(where: { ReferenceKey(resolved: $0.id) == key }),
            let spell = shout.words.first?.spell
        else { return nil }
        return ReferenceKey(resolved: spell.id)
    }

    /// The nearest resident reference within `reach` of `point` that passes `matches`.
    /// One pass, not a sort: a package start asks this once per target. A tie keeps
    /// the first in key order.
    public func nearest(
        to point: SIMD3<Float>, within reach: Float,
        where matches: (RuntimeReferenceEntry) -> Bool
    ) -> ReferenceKey? {
        var best: (key: ReferenceKey, distance: Float)?
        for (entry, distance) in residentPlacedUnsorted(near: point, within: reach)
            where distance < (best?.distance ?? .infinity) && matches(entry)
        {
            best = (entry.key, distance)
        }
        return best?.key
    }

    /// Resident references within `reach` of `point`, nearest first.
    public func residentPlaced(
        near point: SIMD3<Float>, within reach: Float
    ) -> [(entry: RuntimeReferenceEntry, distance: Float)] {
        residentPlacedUnsorted(near: point, within: reach).sorted { $0.distance < $1.distance }
    }

    /// Resident references within `reach` of `point`, in key order.
    private func residentPlacedUnsorted(
        near point: SIMD3<Float>, within reach: Float
    ) -> [(entry: RuntimeReferenceEntry, distance: Float)] {
        let entries = game.streamer.residentReferenceIndex().sortedEntries()
        return entries.compactMap { entry in
            let position = entry.placedReference?.placement.position
                ?? entry.placedActor?.placement.position
            return position.map { (entry: entry, distance: simd_distance($0, point)) }
        }
        .filter { $0.distance <= reach }
    }

    /// `PTDA` object type codes the vanilla templates use, and the test for each.
    public enum PackageObjectType: UInt32 {
        case furniture = 10
        case weapon = 11
        case food = 15
        case bed = 26
        case chair = 27
    }

    public func setDoorsLocked(
        _ locked: Bool, around center: SIMD3<Float>, radius: Float, owner actor: ReferenceKey
    ) -> PackageActionResult {
        guard let bridge = game.scripts.bridge else { return .failed }
        let base = game.streamer.referenceEntry(key: actor)?.placedActor?.base
        let reach = radius > 0 ? radius : Self.doorReach
        for (entry, _) in residentPlaced(near: center, within: reach) {
            guard
                let door = entry.placedReference, door.teleportDestination != nil,
                let lock = bridge.lockState(for: entry.key), lock.isLocked != locked,
                let owner = door.owner, owns(owner, actor: actor, base: base)
            else { continue }
            var state = lock
            state.isLocked = locked
            _ = bridge.write(state.erased, for: entry.key)
        }
        return .done
    }

    /// A door is the actor's when its base, or a faction the actor is in, owns it.
    private func owns(_ owner: FormID, actor: ReferenceKey, base: FormID?) -> Bool {
        if owner == base {
            return true
        }
        guard
            let bridge = game.scripts.bridge,
            let faction = bridge.referenceKey(forFormID: owner)
        else { return false }
        return bridge.isInFaction(actor, faction: faction) == true
    }

    public func find(
        _ selector: Package.Target, around center: SIMD3<Float>, radius: Float
    ) -> [ReferenceKey] {
        let reach = radius > 0 ? radius : Self.findReach
        let candidates = residentPlaced(near: center, within: reach).map(\.entry)
        switch selector.kind {
        case .specificReference:
            let wanted = game.scripts.bridge?.formIDResolver
                .flatMap { ReferenceKey.resolve(FormID(selector.value), using: $0) }
            return candidates.map(\.key).filter { $0 == wanted }
        case .objectID:
            return candidates.filter {
                ConditionFunctions.baseForm(of: $0) == FormID(selector.value)
            }.map(\.key)
        case .objectType:
            guard let type = PackageObjectType(rawValue: selector.value) else { return [] }
            return candidates.filter { matches($0, type) }.map(\.key)
        default:
            return []
        }
    }

    private func matches(_ entry: RuntimeReferenceEntry, _ type: PackageObjectType) -> Bool {
        let base = ConditionFunctions.baseForm(of: entry).rawValue
        let items = game.inventory.runtime?.inventory.baselines.items
        switch type {
        case .weapon:
            return items?.weapons[base] != nil
        case .food:
            return items?.ingestibles[base]?.flags.contains(.food) == true
        case .furniture, .bed, .chair:
            let seats = game.streamer.residentInteraction(reference: entry.formID)?.seats ?? []
            let wanted: UInt16? = type == .bed ? NIFFurnitureMarker.sleepAnimation
                : type == .chair ? NIFFurnitureMarker.sitAnimation : nil
            return seats.contains { wanted == nil || $0.animationType == wanted }
        }
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
