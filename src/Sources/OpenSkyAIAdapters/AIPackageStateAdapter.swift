import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAIPackages
public import OpenSkyCells
import OpenSkyCombatInterface
public import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyDialogueInterface
import OpenSkyFactionsInterface
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyNavigation
import OpenSkyPerceptionInterface
public import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkyRuntimeState
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
    var streamer: any CellStreamerPort { get }
    var worldData: WorldDataStores? { get }
    var worldState: any WorldStateStorePort { get }
}

/// Part of `AIWorldAdapter`, over its own narrow host.
public struct AIPackageStateAdapter {
    public let game: any AIPackageStateHost
    public let packageMoves: AIPackageMovesAdapter
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
        return game.streamer.residentActorEntries()
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
            references: game.streamer.residentReferenceIndex()
        )
        game.runtimeStateWorld.addLiveSeams(to: &context)
        return context
    }

    /// Only the player's gait is known; an NPC leader moves at its package's pace.
    public func packageActorGait(_ actor: ReferenceKey) -> LocomotionGait? {
        actor == .player ? game.gameSession?.locomotion.status.gait : nil
    }

    /// Whether the actor stands inside one package location input, by its radius.
    /// An "in cell" input names an interior cell, so it compares cells, not distance.
    public func isWithin(_ location: Package.Location, actor: ReferenceKey) -> Bool {
        if location.kind == .inCell, let cell = location.formID {
            return game.streamer.cellLocation(of: actor) == .interior(cell)
        }
        guard
            let place = packageMoves.packagePlace(of: location, actor: actor, aliasQuest: nil),
            let position = packageMoves.packageActorPosition(actor)
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
        actor == .player || game.streamer.npcMovement.hasRoom(for: actor)
    }
}
