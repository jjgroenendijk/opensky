// App side of `ClothCoordinator`: the loaded capes, and where each one's actor stands and
// how it is posed this frame (docs/engine/cape-cloth.md).

import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
public import OpenSkyPlayer
public import OpenSkyRendering
public import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
public import simd

/// What `ClothWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
public protocol ClothWorldHost: AnyObject, SendableMetatype {
    var gameSession: (any GameSessionPort)? { get }
    var ragdoll: any RagdollPort { get }
    var renderer: (any RendererPort)? { get }
    var streamer: any CellStreamerPort { get }
    func animatedPose(for key: ReferenceKey) -> [String: float4x4]?
}

public final class ClothWorldAdapter: ClothWorld {
    public let game: any ClothWorldHost
    public private(set) lazy var coordinator = ClothCoordinator(world: self)

    /// Without a stage, as in a test, it registers nothing.
    public init(game: any ClothWorldHost, stage: SessionStage?, isEnabled: Bool = true) {
        self.game = game
        coordinator.isEnabled = isEnabled
        stage?.gameSession.worldTick.register(.cloth) { [weak self] delta in
            self?.coordinator.tick(deltaTime: delta)
        }
    }

    public var clothPlaybacks: [ClothPlayback] {
        let scene = game.renderer?.scene.animations.compactMap { $0 as? ClothPlayback } ?? []
        let player = game.gameSession?.playerBody?.clothAnimation as? ClothPlayback
        return scene + [player].compactMap(\.self)
    }

    public func clothFrame(for cloth: ClothPlayback) -> ClothActorFrame? {
        if cloth.actor == PlayerBody.actorFormID {
            guard
                let session = game.gameSession, let body = session.playerBody,
                let bone = session.playerAnimation?.animatedBonesByName?[cloth.bone]
            else { return nil }
            let pose = session.playerAnimation?.animatedBonesByName ?? [:]
            return ClothActorFrame(
                actorToWorld: body.transform, scale: 1, boneToActor: bone,
                calves: calves(of: .player, pose: pose, actorToWorld: body.transform)
            )
        }
        let streamer = game.streamer
        guard
            let entry = streamer.referenceEntry(formID: cloth.actor),
            let actor = entry.placedActor,
            let pose = game.animatedPose(for: entry.key),
            let bone = pose[cloth.bone]
        else { return nil }
        let frame = streamer.drawnFrame(
            of: entry.key, placed: actor.placement, scale: actor.scale
        )
        return ClothActorFrame(
            actorToWorld: frame.actorToWorld, scale: frame.scale, boneToActor: bone,
            calves: calves(of: entry.key, pose: pose, actorToWorld: frame.actorToWorld)
        )
    }

    public func clothFrameMiss(for cloth: ClothPlayback) -> ClothFrameMiss? {
        if cloth.actor == PlayerBody.actorFormID {
            guard let session = game.gameSession, session.playerBody != nil else {
                return .noPlayerBody
            }
            guard let pose = session.playerAnimation?.animatedBonesByName else {
                return .noPlayerPose
            }
            return pose[cloth.bone] == nil ? .boneNotPosed : nil
        }
        guard
            let entry = game.streamer.referenceEntry(formID: cloth.actor),
            entry.placedActor != nil
        else { return .actorNotLoaded }
        guard let pose = game.animatedPose(for: entry.key) else { return .actorNotPosed }
        return pose[cloth.bone] == nil ? .boneNotPosed : nil
    }

    private func calves(
        of key: ReferenceKey, pose: [String: float4x4], actorToWorld: float4x4
    ) -> [ClothCapsule] {
        guard let ragdoll = game.ragdoll.ragdollDefinition(of: key) else { return [] }
        return ClothCapsule.calves(ragdoll: ragdoll, boneToActor: pose, actorToWorld: actorToWorld)
    }
}
