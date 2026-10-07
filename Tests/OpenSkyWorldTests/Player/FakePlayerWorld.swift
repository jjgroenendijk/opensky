// Plain-value fakes for `PlayerCoordinatorTests`: the renderer side of the
// player and a body provider that records what it was asked to assemble.

import EngineTesting
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
    var playerAppearanceOverride: PlayerAppearanceOverride?
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

/// Assembles nothing: each request answers with a failure on the next drain.
final class FakePlayerRigSource: PlayerRigSource {
    let playerAssetFileSystem: (any GameFileSource)?
    private(set) var requests: [PlayerRigRequest] = []
    private var pending: [PlayerRigLoadResult] = []

    init(fileSystem: (any GameFileSource)? = nil) {
        playerAssetFileSystem = fileSystem
    }

    var bodyRequests: [[FormID]?] {
        requests.filter { !$0.firstPerson }.map(\.equipped)
    }

    var rigRequests: Int {
        requests.filter(\.firstPerson).count
    }

    func requestPlayerRig(_ request: PlayerRigRequest) {
        requests.append(request)
        let reason = request.firstPerson ? "no arms" : "no skin"
        pending.append(PlayerRigLoadResult(
            request: request, result: .failure(.noRenderableGeometry([reason]))
        ))
    }

    func drainPlayerRigs() -> [PlayerRigLoadResult] {
        defer { pending = [] }
        return pending
    }
}

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
