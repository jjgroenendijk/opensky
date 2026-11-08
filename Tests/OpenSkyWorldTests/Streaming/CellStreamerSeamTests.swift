// What the streamer hands the adapters: an actor's inventory holder, the vehicle poses
// it keeps for the movement passes, and the cell-attach steps.

import OpenSkyFormatsESM
import OpenSkyInventoryInterface
@testable import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd
import Testing

@MainActor
struct CellStreamerSeamTests {
    private static let actor = CellStreamerNPCMovementTests.actor

    @Test func onlyThePlayerAndResidentActorsHaveAnInventoryHolder() throws {
        let streamer = try CellStreamerNPCMovementTests.streamerWithWalker()
        #expect(streamer.inventoryHolder(of: .player) == .player)
        let holder = try #require(streamer.inventoryHolder(of: Self.actor))
        #expect(holder.key == Self.actor)
        let base = try #require(streamer.referenceEntry(key: Self.actor)?.placedActor?.base)
        #expect(holder.owner == .actor(base: base))
        let stranger = ReferenceKey.plugin(name: "test.esm", objectID: 0x9999)
        #expect(streamer.inventoryHolder(of: stranger) == nil)
    }

    @Test func theVehicleRulesPublishIntoTheMovementState() throws {
        let streamer = try CellStreamerNPCMovementTests.streamerWithWalker()
        let pose = ReferenceTransformOverride(
            position: SIMD3(300, 50, 0), rotation: SIMD3(0, 0, 1), scale: 1
        )
        streamer.publishCarriedPoses([Self.actor: pose])
        streamer.publishVehicleLinks([Self.actor])
        streamer.setVehiclePose(matrix_identity_float4x4, for: FormID(0x9100))
        #expect(streamer.npcMovementState.carried[Self.actor]?.position == pose.position)
        #expect(streamer.npcMovementState.vehicleLinkedActors == [Self.actor])
        #expect(streamer.npcMovementState.vehiclePoses[FormID(0x9100)] == matrix_identity_float4x4)
    }

    @Test func aRegisteredAttachStepRunsWhenTheCellJoins() throws {
        var attached = 0
        let streamer = try CellStreamerNPCMovementTests.streamerWithWalker { streamer in
            streamer.registerCellAttached(.scripts) { _ in attached += 1 }
        }
        #expect(attached == 1)
        #expect(streamer.cachedAssetCounts == nil)
    }
}
