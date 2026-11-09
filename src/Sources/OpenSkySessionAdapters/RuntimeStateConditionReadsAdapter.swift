import Foundation
import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyAudio
import OpenSkyCells
import OpenSkyCombatInterface
public import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyDialogueInterface
import OpenSkyFactionsInterface
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyPerceptionInterface
import OpenSkyPlayer
import OpenSkyQuestsInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkySave
import OpenSkySaveInterface
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWeather
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
public import OpenSkyWorldState

/// What `RuntimeStateConditionReadsAdapter` reads from the session.
@MainActor
public protocol RuntimeStateConditionReadsHost: AnyObject {
    var actorWorld: any ActorWorldPort { get }
    var crime: any CrimePort { get }
    var factions: any FactionPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var magic: any MagicPort { get }
    var perception: any PerceptionPort { get }
    var scripts: any ScriptPort { get }
    var streamer: any CellStreamerPort { get }
}

/// Part of `RuntimeStateWorldAdapter`, over its own narrow host.
public struct RuntimeStateConditionReadsAdapter {
    public let game: any RuntimeStateConditionReadsHost
    public let core: RuntimeStateCoreAdapter
    public let liveSeams: RuntimeStateLiveSeamsAdapter
}

extension RuntimeStateConditionReadsAdapter {
    /// `aliasQuest` stays nil, because a music condition belongs to no quest.
    /// The references hold the crosshair and every resident actor, so a
    /// combat-target run-on resolves.
    public func conditionContext(
        crosshair: RuntimeReferenceEntry?, globals: GlobalResolution, indexing: [ReferenceKey]
    ) -> ConditionContext {
        let quests = game.scripts.bridge?.questRuntime
        let references = references(crosshair: crosshair, indexing: indexing)
        var context = ConditionContext(
            globals: globals,
            quests: quests?.resolution() ?? .empty,
            aliases: quests?.aliasResolution() ?? .empty,
            actors: core.actorResolution(),
            detection: game.perception.perceptionResolution(),
            magic: game.magic.magicConditionResolution(),
            crime: game.crime.conditionResolution(owning: references.sortedKeys()),
            factions: game.factions.conditionResolution(),
            clock: game.gameSession?.gameClock,
            references: references,
            subject: crosshair?.key,
            target: crosshair?.key
        )
        context.data = core.conditionData()
        liveSeams.addLiveSeams(to: &context)
        return context
    }

    private func references(
        crosshair: RuntimeReferenceEntry?, indexing: [ReferenceKey]
    ) -> RuntimeReferenceIndex {
        var entries = crosshair.map { [$0] } ?? []
        var seen = Set(entries.map(\.key))
        for key in game.actorWorld.combatActors().map(\.key) + indexing {
            guard
                !seen.contains(key),
                let entry = game.streamer.referenceEntry(key: key)
            else { continue }
            seen.insert(key)
            entries.append(entry)
        }
        return RuntimeReferenceIndex(entries: entries)
    }
}
