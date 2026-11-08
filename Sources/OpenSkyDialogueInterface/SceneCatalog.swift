import Foundation
public import OpenSkyFormatsESM
public import OpenSkyGameData

nonisolated public struct SceneCatalog: Sendable {
    package let byFormID: [UInt32: CatalogScene]
    /// Every scene in FormID order.
    public let all: [CatalogScene]
    package let byQuest: [UInt32: [UInt32]]
    package let byEditorID: [String: UInt32]

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
}

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
