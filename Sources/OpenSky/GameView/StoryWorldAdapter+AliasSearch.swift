// App side of the alias fills that read or change the world: the loaded references
// for Find Matching Reference, and the new reference of Create Reference to Object.
// The rules live in `QuestReferenceSearch` and `QuestAliasFiller`
// (docs/engine/quest-state.md).

import OpenSkyCombat
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyPlayer
import OpenSkyQuests
import OpenSkyRendering
import OpenSkyScripting
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
        let feet = game.gameSession.map { gameSession in
            gameSession.movementMode.isPlayerControlled
                ? gameSession.walkController.feetPosition : gameSession.freeFlyCamera.position
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

    /// A new reference of `base` where `anchor` stands, loaded or not. It is a spawn, so
    /// the save keeps it and a cell build places it like a dropped item or an actor.
    func createQuestReference(_ base: FormID, at anchor: ReferenceKey) -> ReferenceKey? {
        guard
            let placement = game.scripts.bridge?.placement(of: anchor),
            let location = placement.location
        else { return nil }
        let spawn = ReferenceSpawnState(
            base: base, location: location, placement: placement.state.transform.placement
        )
        let key = game.worldState.allocateGeneratedKey()
        game.worldState.set(spawn, for: key, in: location)
        return key
    }
}
