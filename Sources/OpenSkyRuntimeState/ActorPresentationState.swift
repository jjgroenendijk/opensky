// How one actor is drawn beyond its records: which head it shows. A change
// rebuilds the cell, as equipment does. The slot has no save tag, so it lasts
// for the session only. An idle prop is not here: `ActorPropPlayback` draws it.

import OpenSkyGameData
import OpenSkyWorldState

nonisolated public enum ActorHeadSource: Equatable, Sendable {
    /// The baked FaceGen mesh and tint, the game's own path.
    case baked
    /// The race and NPC head parts, loaded and tinted one by one.
    case assembled
}

/// A model riding one skeleton bone, such as a lute during an idle.
nonisolated public struct ActorPropAttachment: Equatable, Sendable {
    /// Relative to `Data/meshes`.
    public let modelPath: String
    public let bone: String

    public init(modelPath: String, bone: String) {
        self.modelPath = modelPath
        self.bone = bone
    }
}

nonisolated public struct ActorPresentationState: WorldStateComponent {
    public static let componentKind = WorldStateComponentKind.actorPresentation

    public var headSource: ActorHeadSource

    public init(headSource: ActorHeadSource = .baked) {
        self.headSource = headSource
    }
}

nonisolated extension WorldStateComponentKind {
    public static let actorPresentation = Self(rawValue: "actorPresentation", order: 29)
}
