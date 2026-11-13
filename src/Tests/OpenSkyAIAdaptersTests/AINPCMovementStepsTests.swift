// The NPC movement hooks the AI adapter hangs on the cell streamer.

@testable import OpenSkyAIAdapters
import OpenSkyAIPackages
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPlayer
import OpenSkySessionTesting
import OpenSkyWorldInterface
import OpenSkyWorldState
import Testing

@MainActor
struct AINPCMovementStepsTests {
    private final class Hooks: NPCMovementHooks, NPCCellRebuilds {
        var onNPCMovementPersist: ((NPCMovementPersistence) -> Void)?
        var onNPCCellHandoff: ((NPCMovementPersistence) -> Void)?
        var onNPCLocomotionDrive: ((NPCLocomotionDriveUpdate) -> Void)?
        var onNPCLanding: ((ReferenceKey, WalkLanding) -> Void)?
        var npcStandingActors: (() -> [NPCNeighbour])?
        var npcMovementSpeeds: ((ReferenceKey) -> MovementType.Speeds?)?
        var npcBodyHalfExtents: ((ReferenceKey) -> SIMD3<Float>?)?
        var rebuilt: [CellSceneLocation] = []
        var cellStreamer: Hooks {
            self
        }

        func cellLocation(of key: ReferenceKey) -> CellSceneLocation? {
            nil
        }

        func requestRebuild(of location: CellSceneLocation) {
            rebuilt.append(location)
        }
    }

    private let host = AIHost()
    private let hooks = Hooks()
    private static let actor = ReferenceKey.plugin(name: "base.esm", objectID: 0x20)

    init() {
        host.fakeStreamer.residents.residentReferenceIndexResult = .empty
        AINPCMovementSteps(hosts: host).register(on: hooks)
    }

    @Test func withoutScriptFilesNoBodyShapeIsRead() {
        #expect(hooks.npcBodyHalfExtents == nil)
        #expect(hooks.cellLocation(of: Self.actor) == nil)
    }

    @Test func withoutMovementRecordsAnActorHasNoSpeeds() {
        #expect(hooks.npcMovementSpeeds != nil)
        #expect(hooks.npcMovementSpeeds?(Self.actor) == nil)
    }

    @Test func everyMovementHookIsHung() {
        #expect(hooks.onNPCMovementPersist != nil)
        #expect(hooks.onNPCCellHandoff != nil)
        #expect(hooks.onNPCLocomotionDrive != nil)
        #expect(hooks.onNPCLanding != nil)
        #expect(hooks.npcStandingActors != nil)
        #expect(hooks.rebuilt.isEmpty)
    }
}
