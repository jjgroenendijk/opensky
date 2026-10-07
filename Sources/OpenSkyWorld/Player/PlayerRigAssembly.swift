// The player's rigs are assembled on the cell build queue, because the builder and
// its mesh caches live there. The main actor binds the meshes to the live pose.
// See docs/engine/player-camera.md, "The player body".

import OpenSkyFormatsAnimation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRendering

/// One rig to assemble. A result whose `generation` is not the newest is dropped.
nonisolated public struct PlayerRigRequest: Equatable, Sendable {
    public let generation: Int
    public let firstPerson: Bool
    public let equipped: [FormID]?
    public let appearance: PlayerAppearanceOverride?

    public init(
        generation: Int, firstPerson: Bool, equipped: [FormID]?,
        appearance: PlayerAppearanceOverride?
    ) {
        self.generation = generation
        self.firstPerson = firstPerson
        self.equipped = equipped
        self.appearance = appearance
    }
}

/// The meshes of one rig, before they are bound to a skeleton and a pose.
nonisolated public struct PlayerRigAssembly: Sendable {
    public let assembly: ActorAssembly<ActorRenderAsset>
    /// Chargen slider morphs on the head parts; empty for the arms and a baked head.
    public let faceMorphs: [ObjectIdentifier: FaceMorphBuffer]

    public init(
        assembly: ActorAssembly<ActorRenderAsset>,
        faceMorphs: [ObjectIdentifier: FaceMorphBuffer] = [:]
    ) {
        self.assembly = assembly
        self.faceMorphs = faceMorphs
    }
}

nonisolated public struct PlayerRigLoadResult: Sendable {
    public let request: PlayerRigRequest
    public let result: Result<PlayerRigAssembly, PlayerBodyError>

    public init(request: PlayerRigRequest, result: Result<PlayerRigAssembly, PlayerBodyError>) {
        self.request = request
        self.result = result
    }
}

/// Where the player coordinator gets its rigs: the build queue, or a fake in tests.
public protocol PlayerRigSource: AnyObject {
    /// The mounted archives, for loading the behavior graphs and their clips.
    var playerAssetFileSystem: (any GameFileSource)? { get }
    func requestPlayerRig(_ request: PlayerRigRequest)
    /// Returns and clears every rig finished since the last drain.
    func drainPlayerRigs() -> [PlayerRigLoadResult]
}

nonisolated extension PlayerBody {
    public convenience init(
        rig: PlayerRigAssembly, skeleton: HKASkeleton, pose: PlayerPoseBuffer
    ) {
        self.init(
            assembly: rig.assembly,
            animation: PlayerAnimationPlayback(
                skeleton: skeleton, pose: pose, models: rig.assembly.models.map(\.asset.model)
            ),
            faceMorphs: rig.faceMorphs
        )
    }
}

nonisolated extension PlayerFirstPersonRig {
    public convenience init(
        rig: PlayerRigAssembly, skeleton: HKASkeleton, pose: PlayerPoseBuffer
    ) {
        self.init(
            assembly: rig.assembly,
            animation: PlayerAnimationPlayback(
                skeleton: skeleton, pose: pose, models: rig.assembly.models.map(\.asset.model)
            )
        )
    }
}
