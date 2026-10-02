// Plain-value fakes for `PlayerCoordinatorTests`: the renderer side of the
// player and a body provider that records what it was asked to assemble.

import BehaviorTesting
import GameDataTesting
@testable import OpenSkyBehavior
@testable import OpenSkyFormatsAnimation
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyPhysics
@testable import OpenSkyWorld

@MainActor
final class FakePlayerWorld: PlayerWorld {
    var playerLocomotion: LocomotionBridge? = LocomotionBridge(configuration: .synthetic)
    var isWalkModeActive = true
    var isPlayerGrounded = true
    var playerEquippedSet: [FormID]?
    var playerFirstPersonRig: PlayerFirstPersonRig?
    var areFirstPersonArmsVisible = false
    var firstPersonFOVYRadians: Float? = 1
    var firstPersonArmsEnabled: Bool? = true

    func showPlayerBody(_ body: PlayerBody) throws {}

    func showFirstPersonRig(_ rig: PlayerFirstPersonRig) throws {}

    func setFirstPersonFOVY(radians: Float) {
        firstPersonFOVYRadians = radians
    }

    func setFirstPersonArmsEnabled(_ enabled: Bool) {
        firstPersonArmsEnabled = enabled
    }
}

/// Assembles nothing, so every build records its reason.
nonisolated final class FakePlayerBodyProvider: WorldDataProviding, PlayerBodyProviding {
    let playerAssetFileSystem: (any GameFileSource)?
    private(set) var bodyRequests: [[FormID]?] = []
    private(set) var rigRequests = 0

    init(fileSystem: (any GameFileSource)? = nil) {
        playerAssetFileSystem = fileSystem
    }

    func makePlayerBody(
        skeleton: HKASkeleton,
        pose: PlayerPoseBuffer,
        equipped: [FormID]?
    ) -> Result<PlayerBody, PlayerBodyError> {
        bodyRequests.append(equipped)
        return .failure(.noRenderableGeometry(["no skin"]))
    }

    func makePlayerFirstPersonRig(
        skeleton: HKASkeleton,
        pose: PlayerPoseBuffer,
        equipped: [FormID]?
    ) -> Result<PlayerFirstPersonRig, PlayerBodyError> {
        rigRequests += 1
        return .failure(.noRenderableGeometry(["no arms"]))
    }
}

nonisolated struct NoBodyProvider: WorldDataProviding {}

extension PlayerBehaviorGraph {
    /// A graph over one idle clip and the fixture rig, with no install behind it.
    static func fixture() -> PlayerBehaviorGraph {
        var table = BehaviorObjectTable()
        let root = table.add(
            BehaviorFixture.clipGenerator("idle", animationName: "idle"), at: 0x10
        )
        let files = InMemoryFileSource()
        return PlayerBehaviorGraph(
            instance: BehaviorFixture.instance(root: root, table: table),
            skeleton: HKASkeleton(
                name: "rig",
                bones: [HKABone(name: "root", lockTranslation: false)],
                parentIndices: [-1],
                referencePose: [
                    HKABonePose(translation: .zero, rotation: .identityRotation, scale: .one)
                ]
            ),
            clips: InstallBehaviorClipSource(fileSystem: files),
            referenceSource: InstallBehaviorReferenceSource(
                fileSystem: files, rootPath: PlayerBehaviorGraph.behaviorPath
            )
        )
    }
}
