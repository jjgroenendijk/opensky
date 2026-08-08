// M8.5.1 system menu acceptance against the user's read-only Skyrim SE install.
// `quest_journal.swf` was the worst faulter before issue #136 at 159
// `callDepthExceeded` faults. This test is the standing gate for its real
// in-game System page. Rendered frames and numeric A/B evidence stay in ignored
// logs/.

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
    func vanillaQuestJournalSystemPageBringsUpCleanAndDraws() throws {
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
        // The category data is structural, but bring-up leaves every page
        // hidden. Activation must bring the System fader to the front.
        #expect(SystemMenuMovieBridge.currentState(runtime: runtime) == nil)
        let broughtUp = try render(renderer)

        try renderer.updateSWFRuntime { runtime in
            SystemMenuMovieBridge.activate(runtime: runtime) {}
        }
        for _ in 0 ..< GameViewController.systemMenuActivationTicks {
            try renderer.advanceSWFRuntime()
        }
        let activated = try render(renderer)
        let systemStats = renderer.lastSWFDrawStats
        let system = verifySystemPage(
            runtime: runtime,
            stats: systemStats,
            empty: empty.pixels,
            broughtUp: broughtUp.pixels,
            activated: activated.pixels
        )
        let settings = try openAndVerifySettings(
            renderer: renderer,
            runtime: runtime,
            empty: empty.pixels,
            activated: activated.pixels
        )

        try SystemMenuAcceptanceEvidence.writeFrames(
            empty: empty,
            broughtUp: broughtUp,
            activated: activated,
            settings: settings.frame
        )
        try SystemMenuAcceptanceEvidence.write(
            runtime: runtime,
            stats: systemStats,
            measurement: SystemMenuAcceptanceEvidence.Measurement(
                diagnostics: system.diagnostics,
                rows: system.rows,
                settingsRows: settings.rows,
                state: system.state,
                broughtUpChanged: system.broughtUpChanged,
                activatedChanged: system.activatedChanged,
                settingsChanged: settings.changed,
                settingsTransition: settings.transition
            )
        )
    }

    private struct SystemPageMeasurement {
        let diagnostics: (faults: Int, missingNames: Int)
        let rows: [String]
        let state: String
        let broughtUpChanged: Int
        let activatedChanged: Int
    }

    private struct SettingsMeasurement {
        let frame: (texture: MTLTexture, pixels: [UInt8])
        let rows: [String]
        let changed: Int
        let transition: Int
    }

    private func verifySystemPage(
        runtime: SWFMovieRuntime,
        stats: SWFDrawStats,
        empty: [UInt8],
        broughtUp: [UInt8],
        activated: [UInt8]
    ) -> SystemPageMeasurement {
        // These rows belong to the journal movie's real `SystemPage`, not the
        // title screen and not the engine-side fallback selector.
        let rows = SystemMenuMovieBridge.entryLabels(runtime: runtime)
        #expect(rows.contains("$QUIT"), "movie rows were \(rows)")
        #expect(rows.contains("$SETTINGS"), "movie rows were \(rows)")
        #expect(rows.contains("$CONTROLS"), "movie rows were \(rows)")
        #expect(!rows.contains("$NEW"), "title-screen rows leaked into \(rows)")
        #expect(runtime.movieCallbackNames.contains("ShowMenu"))
        #expect(runtime.invokeLog.unhandled == 0, "the movie made an unanswered engine call")
        let state = SystemMenuMovieBridge.currentState(runtime: runtime) ?? "none"
        #expect(state == "System", "movie state was \(state)")

        let diagnostics = SystemMenuMovieBridge.diagnostics(runtime: runtime)
        #expect(diagnostics.faults == 0, "quest_journal.swf faulted \(diagnostics.faults) times")
        #expect(runtime.tally.unimplementedTotal == 0)
        #expect(runtime.root.children.contains { $0.name == "QuestJournalFader" })
        #expect(stats.drawCalls > 0, "the vanilla menu movie drew nothing")
        let broughtUpChanged = Self.changedPixels(empty, broughtUp)
        #expect(broughtUpChanged > 100, "menu bring-up changed only \(broughtUpChanged) pixels")
        let activatedChanged = Self.changedPixels(empty, activated)
        #expect(activatedChanged > 100, "populated menu changed only \(activatedChanged) pixels")
        return SystemPageMeasurement(
            diagnostics: diagnostics,
            rows: rows,
            state: state,
            broughtUpChanged: broughtUpChanged,
            activatedChanged: activatedChanged
        )
    }

    @MainActor
    private func openAndVerifySettings(
        renderer: Renderer,
        runtime: SWFMovieRuntime,
        empty: [UInt8],
        activated: [UInt8]
    ) throws -> SettingsMeasurement {
        try renderer.updateSWFRuntime { runtime in
            openSettings(runtime: runtime)
        }
        for _ in 0 ..< GameViewController.systemMenuActivationTicks {
            try renderer.advanceSWFRuntime()
        }
        let frame = try render(renderer)
        let rows = SystemMenuMovieBridge.settingsCategoryLabels(runtime: runtime)
        #expect(rows == ["$Gameplay", "$Display", "$Audio"])
        let changed = Self.changedPixels(empty, frame.pixels)
        #expect(changed > 100, "settings changed only \(changed) pixels")
        let transition = Self.changedPixels(activated, frame.pixels)
        #expect(transition > 100, "settings transition changed only \(transition) pixels")
        return SettingsMeasurement(
            frame: frame,
            rows: rows,
            changed: changed,
            transition: transition
        )
    }

    private func openSettings(runtime: SWFMovieRuntime) {
        for _ in 0 ..< 4 {
            #expect(SystemMenuMovieBridge.handle(.move(.down), runtime: runtime))
        }
        #expect(SystemMenuMovieBridge.handle(.button(.accept), runtime: runtime))
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
}

private enum SystemMenuAcceptanceEvidence {
    /// What the run measured, so the evidence writer stays inside the
    /// parameter-count limit.
    struct Measurement {
        let diagnostics: (faults: Int, missingNames: Int)
        let rows: [String]
        let settingsRows: [String]
        let state: String
        let broughtUpChanged: Int
        let activatedChanged: Int
        let settingsChanged: Int
        let settingsTransition: Int
    }

    @MainActor
    static func writeFrames(
        empty: (texture: MTLTexture, pixels: [UInt8]),
        broughtUp: (texture: MTLTexture, pixels: [UInt8]),
        activated: (texture: MTLTexture, pixels: [UInt8]),
        settings: (texture: MTLTexture, pixels: [UInt8])
    ) throws {
        try FileManager.default.createDirectory(
            at: logs,
            withIntermediateDirectories: true
        )
        for (frame, name) in [
            (empty, "system-menu-movie-off.png"),
            (broughtUp, "system-menu-movie-on.png"),
            (activated, "system-menu-movie-activated.png"),
            (settings, "system-menu-movie-settings.png")
        ] {
            try FrameScreenshot.write(
                texture: frame.texture,
                to: logs.appending(path: name)
            )
        }
    }

    static func write(
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
        (pre-#136 measured 159 callDepthExceeded)
        [INFO] unimplemented opcodes: \(runtime.tally.unimplementedTotal)
        [INFO] actions executed: \(runtime.tally.actionsExecuted)
        [INFO] draw calls: \(stats.drawCalls) · skipped items: \(stats.skippedItems)
        [INFO] bring-up off/on changed pixels: \(measurement.broughtUpChanged)
        [INFO] activated changed pixels: \(measurement.activatedChanged)
        [INFO] settings changed pixels: \(measurement.settingsChanged)
        [INFO] system/settings transition pixels: \(measurement.settingsTransition)
        [INFO] distinct missing names: \(measurement.diagnostics.missingNames) \
        (total hits \(runtime.tally.missingTotal))
        [INFO] top missing: \(missing)
        [INFO] movie rows: \(measurement.rows.joined(separator: ", "))
        [INFO] settings rows: \(measurement.settingsRows.joined(separator: ", "))
        [INFO] movie state: \(measurement.state)
        [INFO] host functions registered: \(runtime.hostFunctionNames.joined(separator: ", "))
        [INFO] movie callbacks: \(runtime.movieCallbackNames.joined(separator: ", "))
        [INFO] unhandled invokes: \(runtime.invokeLog.unhandled) of \(runtime.invokeLog.total)
        """
        try report.write(
            to: logs.appending(path: "system-menu-acceptance.log"),
            atomically: true,
            encoding: .utf8
        )
        print(report)
    }

    private static var logs: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "logs")
    }
}
