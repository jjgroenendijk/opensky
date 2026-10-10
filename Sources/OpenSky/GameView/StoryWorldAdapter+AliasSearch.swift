// App side of the Find Matching Reference alias fill: the loaded references with
// their dead and disabled state, and the player's feet for "Closest". The rules
// live in `QuestReferenceSearch` (docs/engine/quest-state.md).

import OpenSkyCombat
import OpenSkyConditions
import OpenSkyQuests
import OpenSkyRendering
import OpenSkyWorld
import OpenSkyWorldState

extension StoryWorldAdapter {
    /// Nil while no cell is loaded.
    func questReferenceSearch() -> QuestReferenceSearch? {
        guard let streamer = game.streamer else { return nil }
        let references = streamer.residentReferenceIndex()
        let store = game.worldState
        let enable = EnableParentResolver(
            delta: { store.delta(for: $0) },
            parent: { [weak streamer] in streamer?.referenceEntry(formID: $0) }
        )
        var context = conditionContext()
        context.references = references
        let entries = references.sortedEntries()
        let feet = game.renderer.map { renderer in
            renderer.movementMode.isPlayerControlled
                ? renderer.walkController.feetPosition : renderer.freeFlyCamera.position
        }
        return QuestReferenceSearch(
            references: references,
            origin: feet,
            context: context,
            registry: conditionRegistry,
            dead: Set(game.actorWorld.combatActors().filter(\.isDead).map(\.key)),
            disabled: Set(entries.filter { !enable.isEnabled($0) }.map(\.key))
        )
    }
}
