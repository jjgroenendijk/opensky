// An idle prop's assets leave the caches with its actor's cell, because the idle's
// own end finds no reference to remove the prop from by then.

import OpenSkyCells
import OpenSkyFormatsESM
import OpenSkyRuntimeState
import OpenSkyTerrain
import OpenSkyWorld
import OpenSkyWorldFixtures
import OpenSkyWorldInterface
import OpenSkyWorldTesting
import Testing

@MainActor
struct CellStreamerActorPropTests {
    @Test func aPropWhoseActorLeftIsDroppedAndEvicted() {
        let runner = ManualCellBuildRunner()
        let streamer = CellStreamerFixture.makeStreamer(runner: runner, radius: 0)
        let actor = FormID(0x0001_2345)
        streamer.actorProps[actor] = ActorPropDraw(
            prop: ActorPropAttachment(modelPath: "clutter\\mug.nif", bone: "WEAPON"),
            assets: CellAssets(
                meshKeys: ["meshes\\clutter\\mug.nif"],
                textureKeys: ["color|mug.dds"]
            )
        )

        streamer.evictUnused(CellAssets())

        #expect(streamer.actorProps.isEmpty)
        #expect(runner.evictedMeshKeys.last == ["meshes\\clutter\\mug.nif"])
        #expect(runner.evictedTextureKeys.last == ["color|mug.dds"])
    }
}
