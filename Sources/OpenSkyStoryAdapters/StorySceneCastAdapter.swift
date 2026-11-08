import Foundation
import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombat
import OpenSkyConditions
import OpenSkyCrime
public import OpenSkyDialogue
public import OpenSkyDialogueInterface
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagic
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyPerception
import OpenSkyQuests
import OpenSkyQuestsInterface
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScripting
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `StorySceneCastAdapter` reads from the session.
@MainActor
public protocol StorySceneCastHost: AnyObject {
    var combat: any CombatPort { get }
    var dialogue: any DialoguePort { get }
    var gameSession: (any GameSessionPort)? { get }
    var packages: any PackagePort { get }
    var scripts: any ScriptPort { get }
    var worldState: any WorldStateStorePort { get }
}

/// Part of `StoryWorldAdapter`, over its own narrow host.
public struct StorySceneCastAdapter {
    public unowned let owner: StoryWorldAdapter
    public unowned let game: any StorySceneCastHost
}

extension StorySceneCastAdapter {
    public var sceneFragments: (any SceneFragmentDispatching)? {
        game.scripts.bridge
    }

    public var sceneSeconds: Double {
        guard let clock = game.gameSession?.gameClock else { return 0 }
        let timescale = game.gameSession?.currentTimescale ?? GameClock.defaultTimescale
        return clock.totalGameSeconds / Double(max(timescale, 1))
    }

    public func runScenePackages(
        _ packages: [FormID], actor: ReferenceKey, owner: ScenePackageOwner
    ) -> ScenePackageState {
        let override = PackageOverride(
            packages: packages,
            owner: PackageOverrideOwner(source: owner.scene, slot: owner.action),
            aliasQuest: self.owner.scenes.catalog.scene(owner.scene)?.quest
        )
        return game.packages.runOverride(override, actor: actor) == .done ? .done : .running
    }

    public func releaseScenePackages(actor: ReferenceKey, owner: ScenePackageOwner) {
        game.packages.clearOverride(
            owner: PackageOverrideOwner(source: owner.scene, slot: owner.action), actor: actor
        )
    }

    /// OpenSky has no observe-combat behaviour, so that status is never set.
    public func sceneActorStatus(_ actor: ReferenceKey) -> SceneActorStatus {
        var status: SceneActorStatus = []
        if game.worldState.component(ActorDeathState.self, for: actor)?.isDead == true {
            status.insert(.dead)
        } else if (game.combat.loop?.activity(of: actor) ?? .notFighting) != .notFighting {
            status.insert(.inCombat)
        }
        if game.dialogue.conversationSpeaker == actor {
            status.insert(.inPlayerDialogue)
        }
        return status
    }

    public func stopQuest(_ quest: FormID) {
        guard
            let runtime = owner.questRuntime,
            let key = runtime.quests.key(for: quest) else { return }
        try? game.scripts.bridge?.stopQuest(for: key)
    }
}
