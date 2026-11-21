// The main menu backdrop and a loading screen both draw through the `LSIS` image space.
// A synthetic DOBJ names a synthetic IMGS whose saturation is 0.75.

import Foundation
import OpenSkyEngineTesting
import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyGameData
@testable import OpenSkyLoading
@testable import OpenSkyMenuAdapters
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkySessionTesting
import Testing

@MainActor
struct LoadScreenImageSpaceTests {
    private let host = MenuHost()

    private static func records() throws -> FakeMenuRecords {
        var dobj = Data("LSIS".utf8)
        dobj.appendUInt32(0x40)
        let data = ESMFixture.tes4()
            + ESMFixture.topGroup("DOBJ", contents: ESMFixture.record(
                "DOBJ", formID: 0x31, data: ESMFixture.field("DNAM", dobj)
            ))
            + ESMFixture.topGroup("IMGS", contents: ESMFixture.record(
                "IMGS", formID: 0x40, data: ESMFixture.field("CNAM", ESMFixture.f32(0.75, 1, 1))
            ))
        let records = FakeMenuRecords()
        records.menuRecords = try MenuRecordData(
            loadOrder: LoadOrderPlugins([("Base.esm", ESMFile(data: data))]),
            settings: GameSettingStore(plugins: [])
        )
        return records
    }

    @Test func theTitleBackdropDrawsThroughTheLoadScreenImageSpace() throws {
        let renderer = try #require(FakeRendererPort())
        host.renderer = renderer
        host.menuRecords = try Self.records()
        let menus = MenuWorldAdapter(game: host, now: { Date(timeIntervalSinceReferenceDate: 0) })
        menus.showTitleBackdrop(true)
        #expect(renderer.loadingCovers.last?.imageSpace?.saturation == 0.75)
    }

    @Test func aLoadingScreenDrawsThroughTheLoadScreenImageSpace() throws {
        let renderer = try #require(FakeRendererPort())
        host.menuRecords = try Self.records()
        let loading = LoadingScreenWorldAdapter(game: host, stage: nil, clock: { Date() })
        let frame = LoadingCoverFrame(
            model: "missing.nif", scale: 1, rotationDegrees: .zero, translation: .zero,
            fieldOfView: 80, cameraPath: nil, text: "Tip", opacity: 1, drawsObject: true
        )
        let scene = loading.presentation.coverScene(frame, renderer: renderer)
        #expect(scene.imageSpace?.saturation == 0.75)
    }

    @Test func withoutRecordsTheCoverKeepsTheWorldsImageSpace() throws {
        let renderer = try #require(FakeRendererPort())
        host.renderer = renderer
        let menus = MenuWorldAdapter(game: host, now: { Date(timeIntervalSinceReferenceDate: 0) })
        menus.showTitleBackdrop(true)
        #expect(renderer.loadingCovers.last?.imageSpace == nil)
    }
}
