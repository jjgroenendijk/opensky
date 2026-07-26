// M8.5.1 system menu acceptance against the user's read-only Skyrim SE install.
// The 8.3.3 measurement rejected `startmenu.swf` on 35 `callDepthExceeded`
// faults; this test is the standing re-measurement of that verdict after the
// `super` resolution fix (issue #136). Rendered frames and the numeric A/B
// evidence stay in ignored logs/.

import Foundation
import Metal
import MetalKit
@testable import opensky
import Testing

struct SystemMenuAcceptanceRealDataTests {
    private static let device: MTLDevice? = {
        guard let device = MTLCreateSystemDefaultDevice(), device.supportsFamily(.metal4)
        else { return nil }
        return device
    }()

    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    private static var canRun: Bool {
        device != nil && dataRoot != nil
    }

    private static let width = 1280
    private static let height = 720

    @Test(.enabled(if: Self.canRun))
    @MainActor
    func vanillaStartMenuBringsUpCleanAndDraws() throws {
        let root = try #require(Self.dataRoot)
        let device = try #require(Self.device)
        let fileSystem = VirtualFileSystem(root: root)
        let renderer = try makeRenderer(device: device)

        let empty = try render(renderer)

        let movie = try SWFMovieLoader(fileSystem: fileSystem).load(
            path: SystemMenuMovieBridge.moviePath
        )
        try renderer.setSWFMovie(movie)
        renderer.swfEnabled = true
        let runtime = try #require(
            try renderer.startSWFRuntime(prepare: SystemMenuMovieBridge.prepare(runtime:))
        )
        // Bring-up alone leaves the movie on its authored placeholders.
        #expect(SystemMenuMovieBridge.entryLabels(runtime: runtime).isEmpty)
        let broughtUp = try render(renderer)

        try renderer.updateSWFRuntime { runtime in
            SystemMenuMovieBridge.activate(runtime: runtime, version: "OpenSky") {}
        }
        for _ in 0 ..< GameViewController.systemMenuActivationTicks {
            try renderer.advanceSWFRuntime()
        }
        let activated = try render(renderer)

        // The vanilla list is engine-populated, so real rows are the proof the
        // `sendMenuProperties` contract is right rather than merely accepted.
        let rows = SystemMenuMovieBridge.entryLabels(runtime: runtime)
        #expect(rows.contains("$QUIT"), "movie rows were \(rows)")
        #expect(rows.contains("$NEW"), "movie rows were \(rows)")
        #expect(
            !rows.contains("$CONTINUE"),
            "OpenSky has no save system, so Continue must not offer itself"
        )
        #expect(runtime.movieCallbackNames.contains("sendMenuProperties"))
        #expect(runtime.invokeLog.unhandled == 0, "the movie made an unanswered engine call")
        let state = SystemMenuMovieBridge.currentState(runtime: runtime) ?? "none"
        #expect(state == "Main", "movie state was \(state)")

        let diagnostics = SystemMenuMovieBridge.diagnostics(runtime: runtime)
        // The 8.3.3 blocker. If this ever regresses, the movie-driven half of
        // the system menu is unusable again and the readout must say so.
        #expect(diagnostics.faults == 0, "startmenu.swf faulted \(diagnostics.faults) times")
        #expect(runtime.tally.unimplementedTotal == 0)
        #expect(runtime.root.children.contains { $0.name == "MenuHolder" })

        let stats = renderer.lastSWFDrawStats
        #expect(stats.drawCalls > 0, "the vanilla menu movie drew nothing")
        let changed = Self.changedPixels(empty.pixels, broughtUp.pixels)
        #expect(changed > 100, "menu bring-up changed only \(changed) pixels")
        // Driving the movie into `Main` currently stages its content off the
        // viewport, so the populated list is addressable but not yet visible.
        // Recorded rather than asserted away — see docs/engine/system-menu.md.
        let activatedChanged = Self.changedPixels(empty.pixels, activated.pixels)

        try writeFrames(empty: empty, broughtUp: broughtUp, activated: activated)
        try writeEvidence(
            runtime: runtime,
            stats: stats,
            measurement: Measurement(
                diagnostics: diagnostics, rows: rows, state: state,
                broughtUpChanged: changed, activatedChanged: activatedChanged
            )
        )
    }

    /// What the run measured, so the evidence writer stays inside the
    /// parameter-count limit.
    private struct Measurement {
        let diagnostics: (faults: Int, missingNames: Int)
        let rows: [String]
        let state: String
        let broughtUpChanged: Int
        let activatedChanged: Int
    }

    @MainActor
    private func writeFrames(
        empty: (texture: MTLTexture, pixels: [UInt8]),
        broughtUp: (texture: MTLTexture, pixels: [UInt8]),
        activated: (texture: MTLTexture, pixels: [UInt8])
    ) throws {
        try FileManager.default.createDirectory(
            at: Self.logs,
            withIntermediateDirectories: true
        )
        for (frame, name) in [
            (empty, "system-menu-movie-off.png"),
            (broughtUp, "system-menu-movie-on.png"),
            (activated, "system-menu-movie-activated.png")
        ] {
            try FrameScreenshot.write(
                texture: frame.texture,
                to: Self.logs.appending(path: name)
            )
        }
    }

    /// Split out so the acceptance body stays inside the strict-lint function
    /// limit; every number here is measured, none is asserted twice.
    private func writeEvidence(
        runtime: SWFMovieRuntime,
        stats: SWFDrawStats,
        measurement: Measurement
    ) throws {
        let missing = runtime.tally.missingNames
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .prefix(12)
            .map { "\($0.key) \($0.value)" }
            .joined(separator: ", ")
        let report = """
        [INFO] movie: \(SystemMenuMovieBridge.moviePath)
        [INFO] faults: \(measurement.diagnostics.faults) \
        (8.3.3 measured 35 callDepthExceeded before issue #136)
        [INFO] unimplemented opcodes: \(runtime.tally.unimplementedTotal)
        [INFO] actions executed: \(runtime.tally.actionsExecuted)
        [INFO] draw calls: \(stats.drawCalls) · skipped items: \(stats.skippedItems)
        [INFO] bring-up off/on changed pixels: \(measurement.broughtUpChanged)
        [INFO] activated changed pixels: \(measurement.activatedChanged) \
        (0 = populated list staged off the viewport)
        [INFO] distinct missing names: \(measurement.diagnostics.missingNames) \
        (total hits \(runtime.tally.missingTotal))
        [INFO] top missing: \(missing)
        [INFO] movie rows: \(measurement.rows.joined(separator: ", "))
        [INFO] movie state: \(measurement.state)
        [INFO] host functions registered: \(runtime.hostFunctionNames.joined(separator: ", "))
        [INFO] movie callbacks: \(runtime.movieCallbackNames.joined(separator: ", "))
        [INFO] unhandled invokes: \(runtime.invokeLog.unhandled) of \(runtime.invokeLog.total)
        """
        try report.write(
            to: Self.logs.appending(path: "system-menu-acceptance.log"),
            atomically: true,
            encoding: .utf8
        )
        print(report)
    }

    /// The engine-side selector must work with no install at all, so the
    /// milestone surface never depends on the movie coming up.
    @Test
    func selectorIsIndependentOfTheMovie() {
        var model = SystemMenuModel()
        model.open()
        model.handle(.move(.down))
        #expect(model.handle(.button(.accept)) == .showSettings)
        #expect(model.settingsRevealed)
    }

    @MainActor
    private func makeRenderer(device: MTLDevice) throws -> Renderer {
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: Self.width, height: Self.height),
            device: device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        return try Renderer(view: view)
    }

    @MainActor
    private func render(_ renderer: Renderer) throws -> (texture: MTLTexture, pixels: [UInt8]) {
        let texture = try renderer.renderOffscreen(
            width: Self.width,
            height: Self.height,
            animationTime: 1
        )
        var pixels = [UInt8](repeating: 0, count: Self.width * Self.height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            texture.getBytes(
                base,
                bytesPerRow: Self.width * 4,
                from: MTLRegionMake2D(0, 0, Self.width, Self.height),
                mipmapLevel: 0
            )
        }
        return (texture, pixels)
    }

    private static func changedPixels(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
        stride(from: 0, to: min(lhs.count, rhs.count), by: 4).reduce(0) { count, index in
            let changed = (0 ..< 3).contains { lhs[index + $0] != rhs[index + $0] }
            return count + (changed ? 1 : 0)
        }
    }

    private static var logs: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "logs")
    }
}
