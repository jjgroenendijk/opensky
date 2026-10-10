// The scenes the runtime can play, in the FormID space of the quest and dialogue
// stores, with the session-stable key their state is filed under.
// See docs/engine/scenes.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated public struct CatalogScene: Equatable, Sendable {
    public let formID: FormID
    public let key: ReferenceKey
    public let scene: Scene
    /// The PNAM quest in the catalog's FormID space. `scene.quest` is relative to
    /// the scene's own plugin, which differs for a DLC scene.
    public let quest: FormID?
    /// From the scene's own plugin to the catalog's space. Nil when they are the same.
    public let translation: FormIDTranslation?

    /// A scene from a plugin whose FormIDs are the catalog's own.
    public init(formID: FormID, key: ReferenceKey, scene: Scene) {
        self.init(formID: formID, key: key, scene: scene, quest: scene.quest)
    }

    public init(
        formID: FormID,
        key: ReferenceKey,
        scene: Scene,
        quest: FormID?,
        translation: FormIDTranslation? = nil
    ) {
        self.formID = formID
        self.key = key
        self.scene = scene
        self.quest = quest
        self.translation = translation
    }

    public var editorID: String {
        scene.editorID ?? formID.description
    }
}

nonisolated public struct SceneCatalog: Sendable {
    private let byFormID: [UInt32: CatalogScene]
    /// Every scene in FormID order.
    public let all: [CatalogScene]
    private let byQuest: [UInt32: [UInt32]]
    private let byEditorID: [String: UInt32]

    public static let empty = SceneCatalog(scenes: [])

    public init(scenes: [CatalogScene]) {
        var byFormID: [UInt32: CatalogScene] = [:]
        var byQuest: [UInt32: [UInt32]] = [:]
        var byEditorID: [String: UInt32] = [:]
        for entry in scenes.sorted(by: { $0.formID.rawValue < $1.formID.rawValue }) {
            byFormID[entry.formID.rawValue] = entry
            if let quest = entry.quest {
                byQuest[quest.rawValue, default: []].append(entry.formID.rawValue)
            }
            if let editorID = entry.scene.editorID {
                byEditorID[editorID.lowercased()] = entry.formID.rawValue
            }
        }
        self.byFormID = byFormID
        all = byFormID.keys.sorted().compactMap { byFormID[$0] }
        self.byQuest = byQuest
        self.byEditorID = byEditorID
    }

    /// The scenes of `store` that `resolver`'s plugin can name, keyed through it.
    /// Pass the quest store's resolver, so a scene's quest is a quest-store FormID.
    public init(store: SceneStore, resolver: FormIDResolver) {
        self.init(scenes: store.scenes.records.compactMap { record in
            guard
                let formID = resolver.localFormID(of: record.id),
                let key = ReferenceKey.resolve(formID, using: resolver)
            else {
                return nil
            }
            let quest = store.scenes.index
                .resolvedID(record.record.quest, fromPlugin: record.sourcePlugin)
                .flatMap { resolver.localFormID(of: $0) }
            let translation = store.scenes.index.resolver(ofPlugin: record.sourcePlugin)
                .map { FormIDTranslation(source: $0, target: resolver) }
            return CatalogScene(
                formID: formID, key: key, scene: record.record, quest: quest,
                translation: translation
            )
        })
    }

    public var count: Int {
        byFormID.count
    }

    public func scene(_ id: FormID) -> CatalogScene? {
        byFormID[id.rawValue]
    }

    public func scene(editorID: String) -> CatalogScene? {
        byEditorID[editorID.lowercased()].flatMap { byFormID[$0] }
    }

    /// Scenes whose PNAM names `quest`, in FormID order.
    public func scenes(ofQuest quest: FormID) -> [CatalogScene] {
        (byQuest[quest.rawValue] ?? []).compactMap { byFormID[$0] }
    }
}
