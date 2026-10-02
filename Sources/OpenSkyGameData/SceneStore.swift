// SCEN lookup by quest, with dialogue actions joined to their topics and
// scene actors joined to the quest's aliases. See docs/formats/scenes.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

/// A scene actor and the quest alias it names. `alias` is nil when the quest has no such alias.
nonisolated public struct SceneActorAlias: Equatable, Sendable {
    public let actor: SceneActor
    public let alias: Quest.Alias?
}

nonisolated public struct SceneStore: Sendable {
    public let scenes: TypedRecordStore<Scene>
    private let scenesByQuest: [ResolvedFormID: [ResolvedFormID]]

    public init(index: RecordIndex) {
        scenes = TypedRecordStore(
            index: index, types: ["SCEN"],
            decode: { try Scene(record: $0.record) }, editorID: \.editorID
        )
        var scenesByQuest: [ResolvedFormID: [ResolvedFormID]] = [:]
        for scene in scenes.records {
            guard let quest = index.resolvedID(scene.record.quest, fromPlugin: scene.sourcePlugin)
            else { continue }
            scenesByQuest[quest, default: []].append(scene.id)
        }
        self.scenesByQuest = scenesByQuest
    }

    public init(plugins: [(name: String, file: ESMFile)]) {
        self.init(index: RecordIndex(plugins: plugins, recordTypes: ["SCEN"]))
    }

    public func scenes(forQuest quest: ResolvedFormID) -> [ResolvedRecord<Scene>] {
        (scenesByQuest[quest] ?? []).compactMap { scenes.record($0) }
    }

    /// The DIAL of each dialogue action, in action order.
    public func dialogueTopics(of scene: ResolvedRecord<Scene>) -> [ResolvedFormID] {
        scene.record.actions.compactMap { action in
            guard case let .dialogue(dialogue) = action.payload else { return nil }
            return scenes.index.resolvedID(dialogue.topic, fromPlugin: scene.sourcePlugin)
        }
    }

    public func actorAliases(
        of scene: ResolvedRecord<Scene>,
        in quest: Quest
    ) -> [SceneActorAlias] {
        scene.record.actors.map {
            SceneActorAlias(actor: $0, alias: quest.alias(id: UInt32(bitPattern: $0.aliasID)))
        }
    }
}
