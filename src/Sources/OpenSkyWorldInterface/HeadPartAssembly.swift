import Foundation
import OpenSkyFormatsCore
public import OpenSkyFormatsESM

nonisolated public struct HeadPartSet: Equatable, Sendable {
    public let parts: [ResolvedHeadPart]
    public let misses: [HeadPartMiss]

    public init(parts: [ResolvedHeadPart], misses: [HeadPartMiss]) {
        self.parts = parts
        self.misses = misses
    }
}

nonisolated public struct ResolvedHeadPart: Equatable, Sendable {
    public let formID: FormID
    public let editorID: String?
    public let partType: HeadPart.PartType?
    public let origin: HeadPartOrigin
    /// Relative to `Data/meshes`.
    public let modelPath: String
    /// TNAM texture set paths, relative to `Data/textures`; nil keeps the mesh's own.
    public let diffuseTexture: String?
    public let normalTexture: String?
    /// HCLF for hair, facial hair, and brows, else the part's CNAM; 0...1.
    public let tint: SIMD3<Float>?
    /// TX04, the FaceGen detail map; a complexion changes it on the face part.
    public var detailTexture: String?
    /// The face tint built from the player's tint layers; the face part only.
    public var faceTintTexture: String?

    public init(
        formID: FormID,
        editorID: String?,
        partType: HeadPart.PartType?,
        origin: HeadPartOrigin,
        modelPath: String,
        diffuseTexture: String?,
        normalTexture: String?,
        tint: SIMD3<Float>?,
        detailTexture: String? = nil,
        faceTintTexture: String? = nil
    ) {
        self.formID = formID
        self.editorID = editorID
        self.partType = partType
        self.origin = origin
        self.modelPath = modelPath
        self.diffuseTexture = diffuseTexture
        self.normalTexture = normalTexture
        self.tint = tint
        self.detailTexture = detailTexture
        self.faceTintTexture = faceTintTexture
    }
}

nonisolated public struct HeadPartMiss: Equatable, Sendable {
    nonisolated public enum Reason: Equatable, Sendable {
        case missingRecord
        /// RNAM names a race list without the actor's race.
        case wrongRace
        case noModel
        /// An HNAM list leads back to a part already taken.
        case cycle
    }

    public let reason: Reason

    public init(
        reason: Reason
    ) {
        self.reason = reason
    }
}

nonisolated public enum HeadPartOrigin: Equatable, Sendable {
    case raceDefault
    case npcOverride
    /// Came along through another part's HNAM list.
    case extraPart
}
