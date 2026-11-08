import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyActorsInterface
import OpenSkyAIPackages
public import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
public import OpenSkyConditions
import OpenSkyCrime
import OpenSkyDialogue
import OpenSkyFactions
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyInventory
import OpenSkyMagic
import OpenSkyNavigation
import OpenSkyPerception
import OpenSkyPerceptionInterface
public import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScripting
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldConditions
public import OpenSkyWorldInterface
public import OpenSkyWorldState
import simd

/// What `AIPackageStateAdapter` reads from the session.
@MainActor
public protocol AIPackageStateHost: AnyObject {
    var combat: any CombatPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var perception: any PerceptionPort { get }
    var renderer: (any RendererPort)? { get }
    var runtimeState: any RuntimeStatePort { get }
    var runtimeStateWorld: any RuntimeStateWorldPort { get }
    var scripts: any ScriptPort { get }
    var streamer: (any CellStreamerPort)? { get }
    var worldData: WorldDataStores? { get }
    var worldState: any WorldStateStorePort { get }
}

/// Part of `AIWorldAdapter`, over its own narrow host.
public struct AIPackageStateAdapter {
    public unowned let owner: AIWorldAdapter
    public unowned let game: any AIPackageStateHost
}

extension AIPackageStateAdapter {
    public func packageLeveledRoll(of actor: ReferenceKey, base: FormID) -> LeveledRoll? {
        guard actor != .player, let roller = game.worldData?.actorValueBaselines?.leveling else {
            return nil
        }
        return game.worldState.leveledRoll(of: actor, base: base, with: roller)
    }

    public func packageResidents() -> [RuntimeReferenceEntry]? {
        guard game.renderer != nil else { return nil }
        return game.streamer?.residentActorEntries()
    }

    public var packageClock: GameClock? {
        game.gameSession?.gameClock
    }

    /// Reads only the store, so it is kept until the next store write.
    private func referenceEnableResolution() -> ReferenceEnableResolution {
        let store = game.worldState
        return store.derived(ReferenceEnableResolution.self, from: store) {
            ReferenceEnableResolution(snapshot: store.snapshot())
        }
    }

    public func packageConditionContext(clock: GameClock) -> ConditionContext {
        var context = ConditionContext(
            globals: game.runtimeState.globalResolution(),
            quests: game.scripts.bridge?.questRuntime?.resolution() ?? .empty,
            aliases: game.scripts.bridge?.questRuntime?.aliasResolution() ?? .empty,
            actors: game.runtimeStateWorld.actorResolution(),
            detection: game.perception.perceptionResolution(),
            referenceEnable: referenceEnableResolution(),
            clock: clock,
            references: game.streamer?.residentReferenceIndex()
                ?? RuntimeReferenceIndex(entries: [])
        )
        game.runtimeStateWorld.addLiveSeams(to: &context)
        return context
    }

    public func packageActorPosition(_ actor: ReferenceKey) -> SIMD3<Float>? {
        guard actor != .player else { return game.gameSession?.locomotion.status.feetPosition }
        guard let streamer = game.streamer else { return nil }
        if let live = streamer.npcTransform(for: actor) {
            return live.position
        }
        return streamer.referenceEntry(key: actor).flatMap(Self.placedPosition)
    }

    /// Only the player's gait is known; an NPC leader moves at its package's pace.
    public func packageActorGait(_ actor: ReferenceKey) -> LocomotionGait? {
        actor == .player ? game.gameSession?.locomotion.status.gait : nil
    }

    /// Whether the actor stands inside one package location input, by its radius.
    /// An "in cell" input names an interior cell, so it compares cells, not distance.
    public func isWithin(_ location: Package.Location, actor: ReferenceKey) -> Bool {
        if location.kind == .inCell, let cell = location.formID {
            return game.streamer?.cellLocation(of: actor) == .interior(cell)
        }
        guard
            let place = owner.packagePlace(of: location, actor: actor, aliasQuest: nil),
            let position = packageActorPosition(actor)
        else { return false }
        return simd_distance(place.point, position) <= Float(max(0, place.radius))
    }

    public func packageActorActivity(_ actor: ReferenceKey) -> PackageActorActivity {
        if game.worldState.component(ActorDeathState.self, for: actor)?.isDead == true {
            return .dead
        }
        if isAIDisabled(actor) {
            return .aiDisabled
        }
        return game.combat.loop?.phase(of: actor)?.isEngaged == true ? .fighting : .free
    }

    public func isAIDisabled(_ actor: ReferenceKey) -> Bool {
        game.scripts.bridge?.scriptedState(of: actor).flag(ScriptedStateName.aiDisabled) == true
    }

    public func packageMoverHasRoom(for actor: ReferenceKey) -> Bool {
        actor == .player || game.streamer?.npcMovement.hasRoom(for: actor) ?? true
    }

    public static func placedPosition(_ entry: RuntimeReferenceEntry) -> SIMD3<Float>? {
        entry.placedActor?.placement.position ?? entry.placedReference?.placement.position
    }
}
