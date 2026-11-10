import Foundation
import OpenSkyActorsInterface
import OpenSkyCamera
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyMenus
public import OpenSkyMenusInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyQuestsInterface
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `MapQuestsAdapter` reads from the session.
@MainActor
public protocol MapQuestsHost: AnyObject {
    var mapWorld: any MapWorldPort { get }
    var journal: any JournalPort { get }
    var runtimeState: any RuntimeStatePort { get }
    var streamer: any CellStreamerPort { get }
    var worldState: any WorldStateStorePort { get }
}

/// Part of `MapWorldAdapter`, over its own narrow host.
public struct MapQuestsAdapter {
    let game: any MapQuestsHost
}

extension MapQuestsAdapter {
    /// Displayed, unfinished objectives of every tracked quest.
    public var questTargets: [QuestTargetMarker] {
        guard let runtime = game.journal.runtime else { return [] }
        let requests = runtime.trackedQuests().flatMap { quest in
            guard let state = attempt({ try runtime.state(of: quest.formID) }) else {
                return [QuestTargetRequest]()
            }
            return QuestTargetResolver.requests(
                quest: quest, state: state,
                text: { [self] in game.mapWorld.text($0.displayText) ?? "Objective \($0.index)" },
                conditionsPass: questTargetCheck(quest: quest.formID, runtime: runtime)
            )
        }
        return QuestTargetResolver.resolve(
            requests,
            alias: { quest, alias in
                runtime.aliasReference(alias: UInt32(bitPattern: alias), in: quest)
            },
            place: { [weak game] key in
                game.flatMap { MapQuestsAdapter(game: $0).currentPosition(of: key) }
                    .map { .placed(position: $0, cell: nil) }
            }
        )
    }

    /// Where a loaded object or actor stands now: moved, or as the plugin placed it.
    private func currentPosition(of key: ReferenceKey) -> SIMD3<Float>? {
        let streamer = game.streamer
        guard let entry = streamer.referenceEntry(key: key) else {
            return nil
        }
        let moved = streamer.npcTransform(for: key)
            ?? game.worldState.component(ReferenceTransformOverride.self, for: key)
        return moved?.position
            ?? entry.placedReference?.placement.position
            ?? entry.placedActor?.placement.position
    }

    private func questTargetCheck(
        quest: FormID, runtime: any QuestRuntimePort
    ) -> (Quest.Target) -> Bool {
        var context = game.runtimeState.conditionContext()
        context.formIDTranslation = runtime.quests.translation(of: quest)
        let evaluator = ConditionEvaluator(context: context)
        return { target in
            QuestTargetResolver.conditionsPass(target, quest: quest, evaluator: evaluator) {
                runtime.aliasReference(alias: UInt32(bitPattern: $0), in: quest)
            }
        }
    }
}
