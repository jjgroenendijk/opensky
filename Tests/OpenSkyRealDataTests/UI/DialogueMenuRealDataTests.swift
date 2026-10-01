// Dialogue menu acceptance on the user's install: `dialoguemenu.swf` still has
// the shape `DialogueMenuMovieBridge` measured, a published conversation is
// read back from the movie's own `EntriesA`, subtitle and `eMenuState`, and an
// open menu changes rendered pixels. Frames go to gitignored `logs/`.

import Foundation
import Metal
import MetalKit
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsSWF
@testable import OpenSkyGameData
@testable import OpenSkyMenus
@testable import OpenSkyRendering
import Testing

struct DialogueMenuRealDataTests {
    private static let width = 1280
    private static let height = 720
    /// Frames a publish needs before the menu's transitions have settled. The
    /// same count `DialogueMenuController.activationTicks` uses, restated
    /// rather than read off it: that constant is main-actor isolated and this
    /// is a `nonisolated` stored default.
    private static let activationTicks = 30

    /// Gitignored run output, resolved through `RepositoryLogs` rather than off
    /// the working directory: the test host's is the volume root, not the checkout.
    private static var logs: URL {
        get throws { try RepositoryLogs.directory("dialogue-menu") }
    }

    // MARK: - Contract

    @Test(.enabled(if: RealDataEnvironment.canRender))
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

    @Test(.enabled(if: RealDataEnvironment.canRender))
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

    @Test(.enabled(if: RealDataEnvironment.canRender))
    @MainActor
    func hudSubtitleFieldTakesALineAndGivesItBack() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let fileSystem = VirtualFileSystem(root: root)
        let runtime = try SWFMovieRuntime(
            movieScene: SWFMovieLoader(fileSystem: fileSystem)
                .load(path: HUDMovieBridge.moviePath)
        )
        runtime.start()
        try HUDMovieBridge.validate(runtime: runtime)
        HUDMovieBridge.initialize(runtime: runtime)
        // The HUD bridge hides the holder, because it ships an authoring sample.
        #expect(!HUDMovieBridge.isSubtitleVisible(runtime: runtime))

        let line = "A subtitle OpenSky published."
        HUDMovieBridge.setSubtitleText(line, runtime: runtime)
        #expect(HUDMovieBridge.subtitleText(runtime: runtime) == line)
        #expect(HUDMovieBridge.isSubtitleVisible(runtime: runtime))

        HUDMovieBridge.clearSubtitleText(runtime: runtime)
        #expect(!HUDMovieBridge.isSubtitleVisible(runtime: runtime))
    }

    // MARK: - Pixels

    @Test(.enabled(if: RealDataEnvironment.canRender))
    @MainActor
    func openMenuChangesRenderedPixels() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let device = try #require(RealDataEnvironment.device)
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

        let changed = RenderedPixels.changedCount(closed.pixels, open.pixels)
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

    @MainActor
    private func makeRenderer(device: MTLDevice) throws -> Renderer {
        try RenderedPixels.offscreenRenderer(device: device, width: Self.width, height: Self.height)
    }

    @MainActor
    private func render(_ renderer: Renderer) throws -> (texture: MTLTexture, pixels: [UInt8]) {
        try RenderedPixels.renderFrame(renderer, width: Self.width, height: Self.height)
    }
}

/// Fixtures and reporting, split off the suite so its own body stays inside the
/// repo's type-length limit.
extension DialogueMenuRealDataTests {
    // MARK: - Helpers

    /// The movie, brought up the way the app brings it up.
    @MainActor
    private func makeMovieRuntime() throws -> SWFMovieRuntime {
        let root = try #require(RealDataEnvironment.dataRoot)
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
        let root = try #require(RealDataEnvironment.dataRoot)
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
}
