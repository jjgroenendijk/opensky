import Foundation
import OpenSkyActors
import OpenSkyCamera
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyCrime
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyMagic
import OpenSkyMenus
public import OpenSkyMenusInterface
import OpenSkyPhysics
import OpenSkyPlayer
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
import simd

/// What `MapQuestsAdapter` reads from the session.
@MainActor
public protocol MapQuestsHost: AnyObject {
    var journal: any JournalPort { get }
    var runtimeState: any RuntimeStatePort { get }
    var streamer: (any CellStreamerPort)? { get }
    var worldState: any WorldStateStorePort { get }
}

/// Part of `MapWorldAdapter`, over its own narrow host.
public struct MapQuestsAdapter {
    public unowned let owner: MapWorldAdapter
    public unowned let game: any MapQuestsHost
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
                text: { [self] in owner.text($0.displayText) ?? "Objective \($0.index)" },
                conditionsPass: questTargetCheck(quest: quest.formID, runtime: runtime)
            )
        }
        return QuestTargetResolver.resolve(
            requests,
            alias: { quest, alias in
                runtime.aliasReference(alias: UInt32(bitPattern: alias), in: quest)
            },
            place: { [weak owner] key in
                owner?.quests.currentPosition(of: key).map { .placed(position: $0, cell: nil) }
            }
        )
    }

    /// Where a loaded object or actor stands now: moved, or as the plugin placed it.
    private func currentPosition(of key: ReferenceKey) -> SIMD3<Float>? {
        guard let streamer = game.streamer, let entry = streamer.referenceEntry(key: key) else {
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
