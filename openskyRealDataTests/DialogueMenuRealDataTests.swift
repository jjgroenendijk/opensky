// M17.3 dialogue menu acceptance against the user's read-only Skyrim SE
// install (issue #205): `dialoguemenu.swf` loads, brings up faultlessly, takes
// the rows OpenSky publishes, and changes rendered pixels when it does.
//
// The three questions this answers, in the order the milestone asks them:
//
// 1. Does the vanilla movie still have the shape `DialogueMenuMovieBridge`
//    measured? The class constants, the required entry points and the list are
//    all asserted against the movie rather than against a copy of them here.
// 2. Does a published conversation reach the movie? Read back out of its own
//    `EntriesA`, its own subtitle field and its own `eMenuState`.
// 3. Does it draw? One offscreen frame with the menu open against one with it
//    closed, compared on changed pixels — the `HUDAcceptanceRealDataTests`
//    pattern.
//
// No game-derived bytes leave the run: the assertions are counts and shapes,
// and the two frames go to gitignored `logs/`.

import Foundation
import Metal
import MetalKit
@testable import opensky
import Testing

struct DialogueMenuRealDataTests {
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
    /// Frames a publish needs before the menu's transitions have settled. The
    /// same count `GameViewController.dialogueActivationTicks` uses, restated
    /// rather than read off it: that constant is main-actor isolated and this
    /// is a `nonisolated` stored default.
    private static let activationTicks = 30

    /// Gitignored run output, resolved off this file rather than off the
    /// working directory: the test host's is the volume root, not the checkout.
    private static var logs: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "logs/dialogue-menu")
    }

    // MARK: - Contract

    @Test(.enabled(if: Self.canRun))
    @MainActor
    func vanillaMovieStillMatchesTheMeasuredContract() throws {
        let runtime = try makeMovieRuntime()
        // Every entry point the bridge drives, checked against the movie rather
        // than against the list in the bridge.
        #expect(DialogueMenuMovieBridge.missingEntryPoints(runtime: runtime).isEmpty)
        // The state vocabulary, read off `DialogueMenuObj` itself. The order of
        // `stateConstantNames` is the movie's own numbering, which is what the
        // bridge writes into `eMenuState`.
        for (index, name) in DialogueMenuMovieBridge.stateConstantNames.enumerated() {
            #expect(
                DialogueMenuMovieBridge.stateConstant(name, runtime: runtime) == index,
                "\(name) is not \(index) in the live movie"
            )
        }
        let diagnostics = DialogueMenuMovieBridge.diagnostics(runtime: runtime)
        #expect(diagnostics.faults == 0)
        #expect(diagnostics.unhandledInvokes == 0)
        #expect(runtime.tally.unimplementedOpcodes.isEmpty)
        // The tally is recorded rather than required to be empty: the movie
        // reaches for CLIK infrastructure OpenSky has no equivalent of, and the
        // AS2 scope decision's rule is that each such name is an accounted
        // no-op. What must not move is the fault count above.
        try writeReport(
            """
            [INFO] dialoguemenu.swf: \(runtime.nodeCount) nodes
            [INFO] faults: \(diagnostics.faults)
            [INFO] unhandled invokes: \(diagnostics.unhandledInvokes)
            [INFO] distinct missing names: \(diagnostics.missingNames)
            [INFO] missing name tally: \(rankedMissingNames(runtime))
            """,
            named: "dialogue-menu-contract.log"
        )
    }

    @Test(.enabled(if: Self.canRun))
    @MainActor
    func publishedConversationReachesTheMovie() throws {
        let runtime = try makeMovieRuntime()
        var model = try makeModel()
        DialogueMenuMovieBridge.publish(model, runtime: runtime)
        settle(runtime)

        let labels = DialogueMenuMovieBridge.topicLabels(runtime: runtime)
        #expect(labels.count == model.topics.count)
        #expect(labels == model.topics.map(\.text))
        #expect(DialogueMenuMovieBridge.selectedIndex(runtime: runtime) == 0)
        #expect(DialogueMenuMovieBridge.speakerNameText(runtime: runtime) == model.speaker)
        #expect(
            DialogueMenuMovieBridge.menuState(runtime: runtime)
                == DialogueMenuMovieBridge.stateConstant(
                    "TOPIC_LIST_SHOWN", runtime: runtime
                )
        )

        // Moving the cursor: the engine owns it, and the movie has to follow.
        model.moveSelection(by: 1)
        DialogueMenuMovieBridge.publish(model, runtime: runtime)
        settle(runtime)
        #expect(DialogueMenuMovieBridge.selectedIndex(runtime: runtime) == 1)

        // Saying a line: the subtitle field takes it and the state moves.
        let line = "A line OpenSky published."
        model.beginResponse(info: FormID(0), runs: [line])
        DialogueMenuMovieBridge.publish(model, runtime: runtime)
        settle(runtime)
        #expect(DialogueMenuMovieBridge.subtitleText(runtime: runtime) == line)
        #expect(
            DialogueMenuMovieBridge.menuState(runtime: runtime)
                == DialogueMenuMovieBridge.stateConstant("TOPIC_CLICKED", runtime: runtime)
        )
        // Nothing is selectable while a line is being said.
        #expect(DialogueMenuMovieBridge.selectedIndex(runtime: runtime) == nil)
    }

    // MARK: - Subtitles on the HUD

    @Test(.enabled(if: Self.canRun))
    @MainActor
    func hudSubtitleFieldTakesALineAndGivesItBack() throws {
        let root = try #require(Self.dataRoot)
        let fileSystem = VirtualFileSystem(root: root)
        let runtime = try SWFMovieRuntime(
            movieScene: SWFMovieLoader(fileSystem: fileSystem)
                .load(path: HUDMovieBridge.moviePath)
        )
        runtime.start()
        try HUDMovieBridge.validate(runtime: runtime)
        HUDMovieBridge.initialize(runtime: runtime)
        // M8.4.2 hides the holder because it ships an authoring sample in it.
        #expect(!HUDMovieBridge.isSubtitleVisible(runtime: runtime))

        let line = "A subtitle OpenSky published."
        HUDMovieBridge.setSubtitleText(line, runtime: runtime)
        #expect(HUDMovieBridge.subtitleText(runtime: runtime) == line)
        #expect(HUDMovieBridge.isSubtitleVisible(runtime: runtime))

        HUDMovieBridge.clearSubtitleText(runtime: runtime)
        #expect(!HUDMovieBridge.isSubtitleVisible(runtime: runtime))
    }

    // MARK: - Pixels

    @Test(.enabled(if: Self.canRun))
    @MainActor
    func openMenuChangesRenderedPixels() throws {
        let root = try #require(Self.dataRoot)
        let device = try #require(Self.device)
        let fileSystem = VirtualFileSystem(root: root)
        let renderer = try makeRenderer(device: device)
        let closed = try render(renderer)

        let movie = try SWFMovieLoader(fileSystem: fileSystem)
            .load(path: DialogueMenuMovieBridge.moviePath)
        try renderer.setSWFMovie(movie)
        renderer.swfEnabled = true
        renderer.swfScale = 1
        let runtime = try #require(
            try renderer.startSWFRuntime(prepare: DialogueMenuMovieBridge.prepare(runtime:))
        )
        try renderer.updateSWFRuntime { runtime in
            DialogueMenuMovieBridge.activate(runtime: runtime) {}
        }
        for _ in 0 ..< Self.activationTicks {
            try renderer.advanceSWFRuntime()
        }
        let model = try makeModel()
        try renderer.updateSWFRuntime { runtime in
            DialogueMenuMovieBridge.publish(model, runtime: runtime)
        }
        for _ in 0 ..< Self.activationTicks {
            try renderer.advanceSWFRuntime()
        }
        let open = try render(renderer)

        let changed = Self.changedPixels(closed.pixels, open.pixels)
        #expect(changed > 100, "open dialogue menu changed only \(changed) pixels")
        #expect(renderer.lastSWFDrawStats.skippedItems == 0)
        #expect(DialogueMenuMovieBridge.diagnostics(runtime: runtime).faults == 0)

        try FileManager.default.createDirectory(
            at: Self.logs, withIntermediateDirectories: true
        )
        try FrameScreenshot.write(
            texture: closed.texture,
            to: Self.logs.appending(path: "dialogue-menu-closed.png")
        )
        try FrameScreenshot.write(
            texture: open.texture,
            to: Self.logs.appending(path: "dialogue-menu-open.png")
        )
        try writeReport(
            """
            [INFO] published rows: \(model.topics.count)
            [INFO] movie rows: \(DialogueMenuMovieBridge.topicLabels(runtime: runtime).count)
            [INFO] closed/open changed pixels: \(changed)
            [INFO] draw calls: \(renderer.lastSWFDrawStats.drawCalls)
            """,
            named: "dialogue-menu-acceptance.log"
        )
    }
}

/// Fixtures and reporting, split off the suite so its own body stays inside the
/// repo's type-length limit.
extension DialogueMenuRealDataTests {
    // MARK: - Helpers

    /// The movie, brought up the way the app brings it up.
    @MainActor
    private func makeMovieRuntime() throws -> SWFMovieRuntime {
        let root = try #require(Self.dataRoot)
        let runtime = try SWFMovieRuntime(
            movieScene: SWFMovieLoader(fileSystem: VirtualFileSystem(root: root))
                .load(path: DialogueMenuMovieBridge.moviePath)
        )
        DialogueMenuMovieBridge.prepare(runtime: runtime)
        runtime.start()
        DialogueMenuMovieBridge.activate(runtime: runtime) {}
        settle(runtime)
        return runtime
    }

    /// A conversation built from the install's own player-category topics.
    ///
    /// Built off `DialogueStore` rather than through `DialogueRuntime`
    /// selection, which needs a running quest and a placed speaker that item
    /// 17.2's own suites already cover. What this gate is about is whether the
    /// movie takes what OpenSky publishes.
    @MainActor
    private func makeModel() throws -> DialogueMenuModel {
        let root = try #require(Self.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let store = DialogueStore(file: file, pluginName: "Skyrim.esm")
        #expect(store.topicCount > 0, "the install declares no dialogue topics")
        let strings = LocalizedStrings(
            vfs: VirtualFileSystem(root: root), pluginName: "Skyrim.esm"
        )
        var entries: [DialogueTopicEntry] = []
        for topic in store.sortedTopics() where topic.category == .player {
            guard entries.count < 4 else { break }
            guard let info = store.infos(for: topic.formID).first else { continue }
            entries.append(
                DialogueTopicEntry(
                    topic: topic.formID,
                    info: info.formID,
                    text: DialogueMenuModel.rowText(
                        topic: topic, info: info, strings: strings
                    ),
                    endsConversation: info.flags.contains(.goodbye)
                )
            )
        }
        #expect(entries.count == 4, "fewer than four player topics resolved")
        // Every row reads as something: an unlabelled row cannot be chosen on
        // purpose, and the fallback chain exists so that stays true.
        #expect(entries.allSatisfy { !$0.text.isEmpty })
        return DialogueMenuModel(speaker: "Speaker", speakerKey: nil, topics: entries)
    }

    @MainActor
    private func settle(_ runtime: SWFMovieRuntime) {
        for _ in 0 ..< Self.activationTicks {
            runtime.advance()
        }
    }

    @MainActor
    private func rankedMissingNames(_ runtime: SWFMovieRuntime) -> String {
        let names: [(name: String, count: Int)] = runtime.tally.missingNames
            .map { (name: $0.key, count: $0.value) }
        let ranked = names.sorted { lhs, rhs in
            lhs.count == rhs.count ? lhs.name < rhs.name : lhs.count > rhs.count
        }
        return ranked.map { "\($0.name)=\($0.count)" }.joined(separator: " ")
    }

    private func writeReport(_ text: String, named name: String) throws {
        try FileManager.default.createDirectory(
            at: Self.logs, withIntermediateDirectories: true
        )
        try text.write(
            to: Self.logs.appending(path: name), atomically: true, encoding: .utf8
        )
        print(text)
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
            width: Self.width, height: Self.height, animationTime: 1
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
            return changed ? count + 1 : count
        }
    }
}
