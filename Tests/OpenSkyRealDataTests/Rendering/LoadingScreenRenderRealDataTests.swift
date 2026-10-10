// A loading screen picked for a door into a known interior, drawn the way a
// transition draws it: the screen's object on the cover layer and its tip in
// the overlay. Frames and the report go to `.logs/loading-screen/`.
// Run with `make test-real T='LoadingScreenRenderRealDataTests'`.

import Foundation
@testable import OpenSkyConditions
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyMenus
@testable import OpenSkyRendering
import OpenSkyTagsTesting
@testable import OpenSkyWorld
import simd
import Testing

@Suite(.tags(.gpu))
struct LoadingScreenRenderRealDataTests {
    private static let width = 1280
    private static let height = 720
    /// The Bannered Mare's location: the inn behind a Whiterun door.
    private static let destination = "WhiterunBanneredMareLocation"

    @Test(.enabled(if: RealDataEnvironment.canRender))
    @MainActor
    func aDoorIntoTheBanneredMareShowsAWhiterunScreen() throws {
        let install = try RealDataInstall.load()
        let root = try #require(RealDataEnvironment.dataRoot)
        let (store, selector) = try Self.selector(root: root)
        var random = ConditionRandom()
        let screen = try #require(selector.pick(random: &random))
        let strings = LocalizedStrings(vfs: install.fileSystem, pluginName: "Skyrim.esm")
        let text = JournalMenuModel.text(
            screen.record.description,
            kind: .strings,
            strings: strings
        )
        let model = try #require(store.model(of: screen))
        let frame = LoadingCoverFrame(
            model: model, scale: screen.record.initialScale ?? 1,
            rotationDegrees: SIMD3<Float>(screen.record.initialRotation
                .map(SIMD3<Float>.init) ?? .zero),
            translation: screen.record.initialTranslation ?? .zero,
            text: text, opacity: 1, drawsObject: true
        )

        let renderer = try RenderedPixels.offscreenRenderer(
            device: install.device,
            width: Self.width,
            height: Self.height
        )
        let dark = try RenderedPixels.renderFrame(renderer, width: Self.width, height: Self.height)
        let renderModel = try install.meshes.model(path: model)
        let radius = install.meshes.bounds(forPath: model)
            .map { simd_length($0.max - $0.min) / 2 } ?? 64
        let view = renderer.freeFlyCamera
        try renderer.setLoadingCover([RenderPlacement(
            model: renderModel,
            transform: frame.objectTransform(
                eye: view.position, yaw: view.yaw, pitch: view.pitch, radius: radius
            ),
            castsShadows: false,
            layer: .loadingCover
        )])
        renderer.uiScene = frame.overlay
        let shown = try RenderedPixels.renderFrame(renderer, width: Self.width, height: Self.height)
        let changed = RenderedPixels.changedCount(dark.pixels, shown.pixels, tolerance: 8)

        let logs = try RepositoryLogs.directory().appending(path: "loading-screen")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try FrameScreenshot.write(
            texture: shown.texture,
            to: logs.appending(path: "bannered-mare.png")
        )
        let lines = [
            "[INFO] \(Self.destination): \(selector.passing().count) "
                + "of \(store.loadScreens.records.count) screens pass",
            "[INFO] picked \(screen.record.editorID ?? "?") model \(model) radius \(radius)",
            "[INFO] text: \(text ?? "none")",
            "[INFO] changed pixels: \(changed)"
        ]
        try lines.joined(separator: "\n").write(
            to: logs.appending(path: "report.log"),
            atomically: true,
            encoding: .utf8
        )
        #expect(changed > Self.width * Self.height / 50, "\(lines)")
        #expect(text?.isEmpty == false)
    }

    /// The screens and a selector for a door into the destination.
    private static func selector(
        root: GameDataRoot
    ) throws -> (PresentationRecordStore, LoadScreenSelector) {
        let index = try RecordIndex(
            plugins: VanillaMasters.load(root: root),
            recordTypes: PresentationRecordStore.recordTypes.union(RecordIndex.referenceRecordTypes)
        )
        let store = PresentationRecordStore(index: index)
        let locations = LocationStore(index: index)
        let location = try #require(locations.location(editorID: destination))
        var context = ConditionContext()
        context.data = ConditionDataResolution(locations: locations)
        let check = LoadScreenSelector.conditionCheck(context: context, destination: location.id)
        return (store, LoadScreenSelector(store: store, check: check))
    }
}
