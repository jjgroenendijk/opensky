// Where a tracked quest's objective points. A target names an alias; the alias
// holds a reference, which may stand in the world, wait in an unloaded cell, lie
// in a container, or be carried. Pure: lookups are passed in.
// See docs/engine/journal.md, quest markers.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyQuestsInterface

/// One shown objective target, before its alias is resolved.
nonisolated public struct QuestTargetRequest: Equatable, Sendable {
    public let quest: FormID
    public let text: String
    public let aliasID: Int32
    /// The QSTA conditions, already evaluated; false hides the target.
    public let conditionsPass: Bool

    public init(
        quest: FormID,
        text: String,
        aliasID: Int32,
        conditionsPass: Bool
    ) {
        self.quest = quest
        self.text = text
        self.aliasID = aliasID
        self.conditionsPass = conditionsPass
    }
}

/// Where a reference is now.
nonisolated public enum QuestTargetPlace: Equatable, Sendable {
    case placed(position: SIMD3<Float>, cell: CellSceneLocation?)
    /// Inside a container or carried: the marker follows the holder.
    case heldBy(ReferenceKey)
}

nonisolated public struct QuestTargetMarker: Equatable, Sendable {
    public let text: String
    /// The reference the marker stands on: the target, or what holds it.
    public let anchor: ReferenceKey
    public let position: SIMD3<Float>
}

nonisolated public enum QuestTargetResolver {
    /// Holders inside holders stop here, so a loop in bad data cannot hang.
    public static let holderDepth = 8

    public static func resolve(
        _ requests: [QuestTargetRequest],
        alias: (FormID, Int32) -> ReferenceKey?,
        place: (ReferenceKey) -> QuestTargetPlace?
    ) -> [QuestTargetMarker] {
        requests.compactMap { request in
            guard request.conditionsPass, let target = alias(request.quest, request.aliasID) else {
                return nil
            }
            var anchor = target
            for _ in 0 ..< holderDepth {
                switch place(anchor) {
                case let .placed(position, _):
                    return QuestTargetMarker(
                        text: request.text, anchor: anchor, position: position
                    )
                case let .heldBy(holder):
                    anchor = holder
                case nil:
                    return nil
                }
            }
            return nil
        }
    }
}

nonisolated extension QuestTargetResolver {
    /// The targets of the shown, unfinished objectives. The game hides a target
    /// whose `QSTA` conditions fail, so `conditionsPass` runs once per target.
    public static func requests(
        quest: Quest,
        state: QuestRuntimeState,
        text: (Quest.Objective) -> String,
        conditionsPass: (Quest.Target) -> Bool
    ) -> [QuestTargetRequest] {
        quest.objectives.flatMap { objective in
            let shown = state.objective(objective.index)
            guard shown.isDisplayed, !shown.isCompleted else { return [QuestTargetRequest]() }
            return objective.targets.map { target in
                QuestTargetRequest(
                    quest: quest.formID, text: text(objective),
                    aliasID: target.aliasID, conditionsPass: conditionsPass(target)
                )
            }
        }
    }
}

nonisolated extension QuestTargetResolver {
    /// A target's conditions run with its alias reference as the subject and the
    /// player as the Target run-on: vanilla's most common check is `GetDead` on the
    /// subject. No conditions pass. See docs/engine/world-map.md.
    public static func conditionsPass(
        _ target: Quest.Target,
        quest: FormID,
        evaluator: ConditionEvaluator,
        alias: (Int32) -> ReferenceKey?
    ) -> Bool {
        guard !target.conditions.isEmpty else { return true }
        var evaluator = evaluator
        evaluator.context.aliasQuest = quest
        evaluator.context.subject = alias(target.aliasID)
        evaluator.context.target = .player
        return evaluator.evaluate(target.conditions).isTrue
    }
}
