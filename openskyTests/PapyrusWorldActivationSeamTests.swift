// The multicast interaction seam end to end (issue #172): a real
// `CellStreamer` raycast activation delivered to both the engine's own
// subscriber and the Papyrus world bridge.
//
// Satellite of `PapyrusWorldActivationTests`, split off to stay under the
// strict-lint type size cap.

import Foundation
@testable import opensky
import simd
import Testing

@MainActor
struct PapyrusWorldActivationSeamTests {
    private static let doorID: UInt32 = 0x21

    private static func key(_ objectID: UInt32) -> ReferenceKey {
        .plugin(name: PapyrusWorldFixture.pluginName, objectID: objectID)
    }

    // MARK: - The multicast seam

    @Test("the interaction fan-out reaches world audio and Papyrus alike")
    func fanOutReachesBothSubscribers() throws {
        let runner = ManualCellBuildRunner()
        let streamer = CellStreamerTests.makeStreamer(runner: runner, radius: 0)
        let entry = try PapyrusWorldFixture.referenceEntry(
            objectID: Self.doorID, scripts: [.init("DoorScript", properties: [])]
        )
        let session = PapyrusWorldFixture.session(
            objects: [PapyrusWorldActivationTests.onActivateScript("DoorScript")], entries: [entry]
        )
        session.bridge.references = streamer

        // Registration order is delivery order: the engine's own audio
        // subscriber stays first, Papyrus runs beside it.
        var audible: [InteractionEvent] = []
        streamer.onInteraction.add { audible.append($0) }
        streamer.onInteraction.add { [weak bridge = session.bridge] event in
            bridge?.handleInteraction(event)
        }
        #expect(streamer.onInteraction.handlerCount == 2)

        let position = CellStreamerTests.center + SIMD3<Float>(10, 0, 0)
        let placed = PapyrusWorldActivationTests.interaction(
            reference: Self.doorID,
            action: .activate
        )
        streamer.update(cameraPosition: CellStreamerTests.center)
        runner.complete(
            CellStreamerTests.coordinate(0, 0),
            with: .success(CellStreamerTests.cellScene(
                location: .exterior(CellStreamerTests.coordinate(0, 0)),
                interactions: [placed.reference: placed],
                staticCollision: Self.collision(reference: Self.doorID, position: position),
                references: RuntimeReferenceIndex(entries: [entry])
            ))
        )
        let ray = CellStreamerTests.interactionRay(
            from: CellStreamerTests.center, to: position
        )
        streamer.update(cameraPosition: CellStreamerTests.center, interactionRay: ray)
        streamer.update(
            cameraPosition: CellStreamerTests.center, interactionRay: ray, activate: true
        )

        #expect(audible.count == 1)
        #expect(audible.first?.target.interaction == placed)
        let activation = try #require(session.worldState.component(
            ReferenceActivationState.self, for: Self.key(Self.doorID)
        ))
        #expect(activation.activationCount == 1)
        #expect(activation.lastActivator == ReferenceKey.player)
        // The streamer, not the fixture, attributed the cell this time.
        #expect(session.worldState.dirtyCount(
            in: .exterior(CellStreamerTests.coordinate(0, 0))
        ) == 1)
        #expect(session.world.eventQueue.contains { $0.functionName == "OnActivate" })
    }

    private static func collision(
        reference: UInt32,
        position: SIMD3<Float>
    ) -> StaticCollisionSet {
        let extent = SIMD3<Float>(repeating: 1)
        var stats = StaticCollisionStats()
        stats.shapeCount = 1
        return StaticCollisionSet(
            location: nil,
            shapes: [StaticCollisionShape(
                reference: FormID(reference),
                transform: MatrixMath.translation(position),
                geometry: .box(halfExtents: extent),
                bounds: ModelBounds(min: position - extent, max: position + extent)
            )],
            stats: stats
        )
    }
}
