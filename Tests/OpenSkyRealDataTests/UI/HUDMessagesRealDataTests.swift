// The HUD movie's notification and help-message entry points: their parameter
// names, and two notifications plus one help message drawn on a frame. The
// report and frames go to `.logs/hud-messages/`.
// Run with `make test-real T='HUDMessagesRealDataTests'`.

import Foundation
import Metal
@testable import OpenSkyFormatsSWF
@testable import OpenSkyGameData
@testable import OpenSkyMenus
@testable import OpenSkyRendering
import TagsTesting
import Testing

@Suite(.tags(.gpu))
struct HUDMessagesRealDataTests {
    private static let width = 1280
    private static let height = 720

    @Test(.enabled(if: RealDataEnvironment.canRender))
    @MainActor
    func notificationsAndHelpDrawOnTheHUD() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let device = try #require(RealDataEnvironment.device)
        let renderer = try RenderedPixels.offscreenRenderer(
            device: device,
            width: Self.width,
            height: Self.height
        )
        let movie = try SWFMovieLoader(fileSystem: VirtualFileSystem(root: root))
            .load(path: HUDMovieBridge.moviePath)
        try renderer.setSWFMovie(movie)
        let runtime = try #require(try renderer.startSWFRuntime())
        try HUDMovieBridge.validate(runtime: runtime)
        HUDMovieBridge.initialize(runtime: runtime)
        var lines = HUDMovieBridge.messageEntryPoints.map { name in
            let parameters = HUDMovieBridge.parameterNames(of: name, runtime: runtime)
            return "[INFO] \(name)(\(parameters?.joined(separator: ", ") ?? "missing"))"
        }
        let before = try RenderedPixels.renderFrame(
            renderer,
            width: Self.width,
            height: Self.height
        )
        try renderer.updateSWFRuntime { runtime in
            HUDMovieBridge.showNotification("Quest started: Unbound", runtime: runtime)
            HUDMovieBridge.showNotification("Added Iron Sword", runtime: runtime)
            HUDMovieBridge.setHelpMessage("Press Jump to jump.", runtime: runtime)
        }
        for _ in 0 ..< 20 {
            try renderer.updateSWFRuntime { _ in }
        }
        let after = try RenderedPixels.renderFrame(renderer, width: Self.width, height: Self.height)
        let changed = RenderedPixels.changedCount(before.pixels, after.pixels, tolerance: 8)
        lines
            .append("[INFO] changed pixels with two notifications and one help message: \(changed)")
        let logs = try RepositoryLogs.directory().appending(path: "hud-messages")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try FrameScreenshot.write(
            texture: before.texture,
            to: logs.appending(path: "hud-messages-off.png")
        )
        try FrameScreenshot.write(
            texture: after.texture,
            to: logs.appending(path: "hud-messages-on.png")
        )
        try lines.joined(separator: "\n").write(
            to: logs.appending(path: "report.txt"), atomically: true, encoding: .utf8
        )
        print(lines.joined(separator: "\n"))
        #expect(HUDMovieBridge.parameterNames(of: "ShowMessage", runtime: runtime) != nil)
        #expect(changed > 100)
    }
}
