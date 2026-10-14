// The scene seam the condition functions read. Built from the catalog and the
// stored scene states, not from a `SceneRuntime`: building a runtime builds a
// condition context, which would build this seam again.

import Foundation
import OpenSkyDialogueInterface
import OpenSkyFormatsESM
import OpenSkyQuestsInterface
import OpenSkyWorldState

extension SceneCoordinator {
    /// Completed actions by their `INAM` index; an action with none keeps its position.
    public func conditionResolution(aliases: QuestAliasResolution) -> SceneConditionResolution {
        var playing: [FormID: Set<UInt32>] = [:]
        var actors: Set<ReferenceKey> = []
        for entry in catalog.all {
            guard let state = dialogue.store.component(SceneRuntimeState.self, for: entry.key)
            else { continue }
            let actions = entry.scene.actions
            playing[entry.formID] = Set(state.completed.map { position in
                actions.indices.contains(Int(position))
                    ? actions[Int(position)].index ?? position : position
            })
            guard state.holdsActors, let quest = entry.quest else { continue }
            for actor in entry.scene.actors where actor.aliasID >= 0 {
                if let reference = aliases.reference(alias: UInt32(actor.aliasID), in: quest) {
                    actors.insert(reference)
                }
            }
        }
        return SceneConditionResolution(playing: playing, actors: actors)
    }
}
