// A loading screen cover is the game's scene: its camera, its three lights, and the
// path's camera place. A model or mist that fails to load still leaves the scene,
// and later tips come from the coordinator.

import Foundation
import OpenSkyEngineTesting
import OpenSkyFormatsTesting
import OpenSkyGameData
@testable import OpenSkyLoading
@testable import OpenSkyMenuAdapters
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkySessionTesting
import Testing

@MainActor
struct LoadingScreenCoverTests {
    private typealias Fixture = ESMFixture
    private let host = MenuHost()

    private static let frame = LoadingCoverFrame(
        model: "missing.nif", scale: 1, rotationDegrees: .zero, translation: .zero,
        fieldOfView: 80, cameraPath: "Cameras\\Path.nif", text: "Tip", opacity: 1,
        drawsObject: true
    )

    private func loading() -> LoadingScreenWorldAdapter {
        host.menuRecords = FakeMenuRecords()
        return LoadingScreenWorldAdapter(game: host, stage: nil, clock: { Date() })
    }

    @Test func theCoverIsTheGamesSceneWhenItsModelsFail() throws {
        let renderer = try #require(FakeRendererPort())
        let loading = loading()
        let scene = loading.presentation.coverScene(Self.frame, renderer: renderer)
        #expect(scene.pointLights.count == 3)
        #expect(scene.camera?.view.position == LoadingScreenScene.cameraBase)
        #expect(scene.camera?.horizontalFieldOfView == LoadingScreenScene.horizontalFieldOfView(80))
        #expect(scene.placements.isEmpty)
        #expect(loading.state.failedModels == ["missing.nif", LoadingScreenScene.mistPath])
    }

    @Test func thePathNodeMovesTheCamera() throws {
        let renderer = try #require(FakeRendererPort())
        let loading = loading()
        let paths = AssetLoader<String, LoadingCameraPath>(
            worker: ImmediateAssetLoadWorker { _ in
                LoadingCameraPath(sequence: nil, channel: nil, rest: [0, -25, 35])
            }
        )
        paths.prefetch("Cameras\\Path.nif")
        _ = paths.drain()
        loading.state.cameraPaths = paths
        let scene = loading.presentation.coverScene(Self.frame, renderer: renderer)
        #expect(scene.camera?.view.position == [-50, 625, 115])
    }

    @Test func laterTipsComeFromTheCoordinator() {
        let loading = loading()
        loading.state.movieText = "First"
        loading.state.shownTip = "First"
        #expect(loading.state.requestTip() == "First")
        host.fakeLoadingScreens.nextTipResult = "Second"
        #expect(loading.state.requestTip() == "Second")
    }

    @Test func everyScreenModelGetsItsMarkerRead() throws {
        let records = FakeMenuRecords()
        records.presentationRecords = try PresentationRecordStore(plugins: [(
            "Base.esm",
            Fixture.plugin(records: [
                Fixture.recordBytes("STAT", formID: 0x60, fields: [
                    ("EDID", Fixture.zstring("Claw")), ("MODL", Fixture.zstring("claw.nif"))
                ]),
                Fixture.recordBytes("LSCR", formID: 0x50, fields: [
                    ("EDID", Fixture.zstring("Screen")), ("NNAM", Fixture.u32(0x60))
                ])
            ])
        )])
        host.menuRecords = records
        let loading = LoadingScreenWorldAdapter(game: host, stage: nil, clock: { Date() })
        #expect(loading.assetLoaders.modelMarkerLoader() != nil)
        host.menuRecords = nil
        #expect(loading.assetLoaders.modelMarkerLoader() == nil)
    }
}
