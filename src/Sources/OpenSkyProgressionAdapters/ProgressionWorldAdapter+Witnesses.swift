import Foundation
import OpenSkyActors
import OpenSkyAudio
import OpenSkyCells
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
import OpenSkyQuestsInterface
import OpenSkyRuntimeState
import OpenSkyScripting
import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState

/// Witnesses that forward to the narrow parts of `ProgressionWorldAdapter`.
extension ProgressionWorldAdapter {
    public func nearestTrainer() -> TrainerOffer? {
        training.nearestTrainer()
    }

    public func trainerOffer(for key: ReferenceKey) -> TrainerOffer? {
        training.trainerOffer(for: key)
    }

    public func playerGold() -> Int {
        training.playerGold()
    }

    public func payTrainer(_ gold: Int, to trainer: ReferenceKey) -> Bool {
        training.payTrainer(gold, to: trainer)
    }

    public func perksChanged(_ runtime: PerkRuntime) {
        effects.perksChanged(runtime)
    }

    public func perksFromActiveEffects(on holder: ActorValueHolder) -> Set<ReferenceKey> {
        effects.perksFromActiveEffects(on: holder)
    }

    public func setPerkQuestStage(_ stage: UInt16, quest: FormID, fromPlugin plugin: String) {
        effects.setPerkQuestStage(stage, quest: quest, fromPlugin: plugin)
    }

    public func reconcileAbilities(on holder: ActorValueHolder, perks: PerkRuntime) {
        effects.reconcileAbilities(on: holder, perks: perks)
    }

    public func playerBeastTree() -> BeastPerkTree? {
        effects.playerBeastTree()
    }

    public func globalValue(editorID: String) -> Float? {
        effects.globalValue(editorID: editorID)
    }

    public func setGlobalValue(_ value: Float, editorID: String) {
        effects.setGlobalValue(value, editorID: editorID)
    }
}
