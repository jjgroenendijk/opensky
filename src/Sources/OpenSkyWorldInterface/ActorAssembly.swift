import Foundation
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRenderResources
public import simd

nonisolated public struct ActorAssembly<Asset> {
    public let actor: FormID
    public let visual: ResolvedActorVisual
    public let transform: float4x4
    public let models: [AssembledActorModel<Asset>]
    public let skips: [ActorAssemblySkip]

    public var isRenderable: Bool {
        !models.isEmpty
    }

    public init(
        actor: FormID,
        visual: ResolvedActorVisual,
        transform: float4x4,
        models: [AssembledActorModel<Asset>],
        skips: [ActorAssemblySkip]
    ) {
        self.actor = actor
        self.visual = visual
        self.transform = transform
        self.models = models
        self.skips = skips
    }
}

nonisolated public struct ActorAssemblySkip: Equatable, Sendable {
    nonisolated public enum Reason: Equatable, Sendable {
        case appearance
        case missingAsset
        case invalidAsset
        case noCoreGeometry
    }

    nonisolated public enum Subject: Equatable, Sendable {
        case appearance(AppearanceSkip)
        case skeleton(path: String)
        case model(role: ActorModelRole, path: String)
        case actor(FormID)
    }

    public let subject: Subject
    public let reason: Reason

    public init(
        subject: Subject,
        reason: Reason
    ) {
        self.subject = subject
        self.reason = reason
    }
}

nonisolated public struct AssembledActorModel<Asset> {
    public let role: ActorModelRole
    public let path: String
    public let asset: Asset

    public init(
        role: ActorModelRole,
        path: String,
        asset: Asset
    ) {
        self.role = role
        self.path = path
        self.asset = asset
    }
}

nonisolated public enum ActorModelRole: Equatable, Sendable {
    case body(ResolvedBodyPart)
    case faceGenHead(tintPath: String?)
    /// A drawn weapon or an idle prop riding a bone.
    case attachment(ResolvedAttachment)
    /// One part of an assembled head.
    case headPart(ResolvedHeadPart)
}

nonisolated extension AssembledActorModel: Sendable where Asset: Sendable {}

nonisolated extension ActorAssembly: Sendable where Asset: Sendable {}
