import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

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

nonisolated public enum ActorHeadSource: Equatable, Sendable {
    /// The baked FaceGen mesh and tint, the game's own path.
    case baked
    /// The race and NPC head parts, loaded and tinted one by one.
    case assembled
}
