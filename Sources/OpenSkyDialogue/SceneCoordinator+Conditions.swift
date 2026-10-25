// The scene seam the condition functions read. Built from the catalog and the
// stored scene states, not from a `SceneRuntime`: building a runtime builds a
// condition context, which would build this seam again.

import Foundation
import OpenSkyDialogueInterface
import OpenSkyFormatsESM
import OpenSkyQuestsInterface
import OpenSkyWorldState

/// The part of the scene seam that does not depend on the aliases.
struct SceneConditionBase {
    var playing: [FormID: Set<UInt32>] = [:]
    /// The alias of each actor a playing scene holds, resolved on every read because
    /// an alias can be filled again without a scene-state write.
    var heldAliases: [(alias: UInt32, quest: FormID)] = []
}

extension SceneCoordinator {
    /// Completed actions by their `INAM` index; an action with none keeps its position.
    public func conditionResolution(aliases: QuestAliasResolution) -> SceneConditionResolution {
        let states = dialogue.store.revision(of: [.scene])
        let base = conditionCache.value(for: states, build: conditionBase)
        var actors: Set<ReferenceKey> = []
        for held in base.heldAliases {
            if let reference = aliases.reference(alias: held.alias, in: held.quest) {
                actors.insert(reference)
            }
        }
        return SceneConditionResolution(playing: base.playing, actors: actors)
    }

    private func conditionBase() -> SceneConditionBase {
        var base = SceneConditionBase()
        for entry in catalog.all {
            guard let state = dialogue.store.component(SceneRuntimeState.self, for: entry.key)
            else { continue }
            let actions = entry.scene.actions
            base.playing[entry.formID] = Set(state.completed.map { position in
                actions.indices.contains(Int(position))
                    ? actions[Int(position)].index ?? position : position
            })
            guard state.holdsActors, let quest = entry.quest else { continue }
            for actor in entry.scene.actors where actor.aliasID >= 0 {
                base.heldAliases.append((UInt32(actor.aliasID), quest))
            }
        }
        return base
    }
}
