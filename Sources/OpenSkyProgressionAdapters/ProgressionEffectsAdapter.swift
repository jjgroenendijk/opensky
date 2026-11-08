import Foundation
import OpenSkyActors
public import OpenSkyCells
import OpenSkyCombat
import OpenSkyConditions
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMagic
import OpenSkyMenus
import OpenSkyPlayer
public import OpenSkyProgression
public import OpenSkyProgressionInterface
import OpenSkyQuests
import OpenSkyRuntimeState
import OpenSkyScripting
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldConditions
public import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `ProgressionEffectsAdapter` reads from the session.
@MainActor
public protocol ProgressionEffectsHost: AnyObject {
    var journalMenu: any JournalMenuPort { get }
    var magic: any MagicPort { get }
    var perks: any PerkPort { get }
    var playerBeastForm: PlayerBeastForm { get }
    var runtimeState: any RuntimeStatePort { get }
    var scripts: any ScriptPort { get }
    var worldData: WorldDataStores? { get }
}

/// Part of `ProgressionWorldAdapter`, over its own narrow host.
public struct ProgressionEffectsAdapter {
    public unowned let owner: ProgressionWorldAdapter
    public unowned let game: any ProgressionEffectsHost
}

extension ProgressionEffectsAdapter {
    public func perksChanged(_ runtime: PerkRuntime) {
        game.magic.caster?.perks = runtime
    }

    public func perksFromActiveEffects(on holder: ActorValueHolder) -> Set<ReferenceKey> {
        guard
            let effects = game.magic.effects,
            let perks = game.perks.runtime?.perks
        else { return [] }
        return ActiveEffectPerks.perks(
            of: effects.active(on: holder), effects: effects.effects, perks: perks
        )
    }

    /// Through the script bridge, as `SetStage` does, so the stage fragment runs. A
    /// quest of another plugin than the quest store's is not resolved.
    public func setPerkQuestStage(_ stage: UInt16, quest: FormID, fromPlugin plugin: String) {
        guard
            let quests = game.journalMenu.questRuntime,
            plugin
                .caseInsensitiveCompare(game.worldData?.magicItemPluginName ?? "") == .orderedSame,
            let key = quests.quests.key(for: quest)
        else { return }
        if let bridge = game.scripts.bridge {
            _ = try? bridge.setQuestStage(stage, for: key)
        } else {
            _ = try? quests.setStage(stage, on: quest)
        }
    }

    public func reconcileAbilities(on holder: ActorValueHolder, perks: PerkRuntime) {
        game.magic.reconcilePerkAbilities(on: holder, perks: perks)
    }

    public func playerBeastTree() -> BeastPerkTree? {
        switch game.playerBeastForm {
        case .werewolf: .werewolf
        case .vampireLord: .vampireLord
        case .none, .otherBeast: nil
        }
    }

    public func globalValue(editorID: String) -> Float? {
        game.runtimeState.runtimeStateGlobal(editorID: editorID)?.currentValue
    }

    public func setGlobalValue(_ value: Float, editorID: String) {
        game.runtimeState.setGlobalValue(value, editorID: editorID)
    }
}
