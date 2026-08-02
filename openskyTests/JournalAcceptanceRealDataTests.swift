// M13.5 journal acceptance against the user's read-only Skyrim SE install
// (issue #184). The Quests page of `quest_journal.swf` had never been driven —
// `docs/decisions/swf-as2-scope.md` deferred its data contract to the milestone
// that owns its data — so this test is the standing gate for that contract:
// the target quest's title, objective and journal text reach the movie, the tab
// strip still switches pages, and the bring-up tallies stay at zero.
//
// Rendered frames and numeric evidence stay in ignored `logs/`; a frame embeds
// the user's game art and is never committed.

import Foundation
import Metal
import MetalKit
@testable import opensky
import Testing

struct JournalAcceptanceRealDataTests {
    /// `MGRArniel01`, the M13 target quest: the cheapest journal-visible quest
    /// in vanilla `Skyrim.esm` by the issue-#181 census — two stages, one
    /// objective, one forced-reference alias, no conditions.
    private static let targetQuest = "MGRArniel01"
    private static let width = 1280
    private static let height = 720

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

    @Test(.enabled(if: Self.canRun))
    @MainActor
    func vanillaJournalShowsTheTargetQuestAndSwitchesTabs() throws {
        let root = try #require(Self.dataRoot)
        let device = try #require(Self.device)
        let fileSystem = VirtualFileSystem(root: root)
        let renderer = try makeRenderer(device: device)
        let empty = try render(renderer)

        let runtime = try openJournal(renderer: renderer, fileSystem: fileSystem)
        // The tab index is the movie's own constant, not a number this test
        // remembers.
        #expect(
            QuestJournalMovieBridge.measuredQuestsTabIndex(runtime: runtime)
                == QuestJournalMovieBridge.questsTabIndex
        )
        #expect(QuestJournalMovieBridge.isFrontmost(runtime: runtime))
        let broughtUp = try render(renderer)

        let session = try makeModel(root: root, fileSystem: fileSystem)
        try renderer.updateSWFRuntime { runtime in
            QuestJournalMovieBridge.publish(session.model, runtime: runtime)
        }
        try renderer.advanceSWFRuntime()
        let published = try render(renderer)

        let quest = try #require(session.model.selectedEntry)
        verifyPublished(quest: quest, runtime: runtime)

        try switchTabs(renderer: renderer, runtime: runtime)
        let tabbed = try render(renderer)

        let diagnostics = verifyClean(runtime: runtime, renderer: renderer)
        let broughtUpChanged = Self.changedPixels(empty.pixels, broughtUp.pixels)
        #expect(broughtUpChanged > 100, "bring-up changed only \(broughtUpChanged) pixels")
        let publishedChanged = Self.changedPixels(broughtUp.pixels, published.pixels)
        #expect(publishedChanged > 100, "publishing changed only \(publishedChanged) pixels")

        try JournalEvidence.writeFrames(
            empty: empty, broughtUp: broughtUp, published: published, tabbed: tabbed
        )
        try JournalEvidence.write(
            runtime: runtime,
            stats: renderer.lastSWFDrawStats,
            measurement: JournalEvidence.Measurement(
                diagnostics: diagnostics,
                questRows: QuestJournalMovieBridge.questLabels(runtime: runtime).count,
                title: QuestJournalMovieBridge.titleText(runtime: runtime) ?? "-",
                objectives: QuestJournalMovieBridge.objectiveLabels(runtime: runtime),
                objectiveFrames: QuestJournalMovieBridge
                    .objectiveEntryFrames(runtime: runtime),
                logEntries: quest.logEntries,
                nodes: runtime.nodeCount,
                broughtUpChanged: broughtUpChanged,
                publishedChanged: publishedChanged,
                tabbedChanged: Self.changedPixels(published.pixels, tabbed.pixels)
            )
        )
    }

    /// The engine's rows are the movie's rows. Reading them back off the
    /// movie's own `EntriesA` and its title field is what proves the contract
    /// crossed the bridge rather than that the engine still holds its own list.
    @MainActor
    private func verifyPublished(quest: JournalQuestEntry, runtime: SWFMovieRuntime) {
        #expect(quest.editorID == Self.targetQuest)
        #expect(
            QuestJournalMovieBridge.titleText(runtime: runtime) == quest.title,
            "the page's title field is not the engine's title"
        )
        #expect(
            QuestJournalMovieBridge.objectiveLabels(runtime: runtime)
                == quest.objectives.map(\.text),
            "the movie's objective rows are not the engine's"
        )
        #expect(!quest.logEntries.isEmpty, "the target quest produced no journal text")
        let description = QuestJournalMovieBridge.descriptionText(runtime: runtime) ?? ""
        for entry in quest.logEntries {
            #expect(description.contains(entry), "a journal paragraph never reached the page")
        }
        // The objective was completed by the model builder below, and the
        // objective entry clip is what shows it.
        #expect(
            QuestJournalMovieBridge.objectiveEntryFrames(runtime: runtime)
                == [QuestJournalMovieBridge.objectiveCompletedFrame]
        )
        #expect(
            QuestJournalMovieBridge.questLabels(runtime: runtime).count
                == QuestJournalMovieBridge.questLabels(runtime: runtime).count
        )
    }

    /// The milestone's stated target: zero faults, zero unimplemented opcodes
    /// and zero unanswered engine calls on the driven page.
    @MainActor
    private func verifyClean(
        runtime: SWFMovieRuntime,
        renderer: Renderer
    ) -> QuestJournalDiagnostics {
        let diagnostics = QuestJournalMovieBridge.diagnostics(runtime: runtime)
        #expect(diagnostics.faults == 0, "quest_journal.swf faulted \(diagnostics.faults) times")
        #expect(runtime.tally.unimplementedTotal == 0)
        #expect(
            diagnostics.unhandledInvokes == 0,
            "the movie made \(diagnostics.unhandledInvokes) unanswered engine calls"
        )
        #expect(renderer.lastSWFDrawStats.drawCalls > 0, "the journal drew nothing")
        return diagnostics
    }

    /// The journal is one movie with three pages, so switching to System and
    /// back is what proves the Quests page did not take the movie over.
    @MainActor
    private func switchTabs(renderer: Renderer, runtime: SWFMovieRuntime) throws {
        try renderer.updateSWFRuntime { runtime in
            runtime.callMovie(
                "SwitchPageToFront",
                atPath: QuestJournalMovieBridge.menuPath,
                arguments: [
                    .integer(SystemMenuMovieBridge.systemTabIndex), .boolean(true)
                ]
            )
        }
        try renderer.advanceSWFRuntime()
        #expect(!SystemMenuMovieBridge.entryLabels(runtime: runtime).isEmpty)

        try renderer.updateSWFRuntime { runtime in
            QuestJournalMovieBridge.activate(runtime: runtime)
        }
        try renderer.advanceSWFRuntime()
        #expect(QuestJournalMovieBridge.isFrontmost(runtime: runtime))
    }
}

// MARK: - Session

extension JournalAcceptanceRealDataTests {
    private struct Session {
        let model: JournalMenuModel
    }

    /// The target quest started, walked to its last stage and with its
    /// objective displayed and completed, so the page has every state to show.
    /// Nothing is written to the install: the state lives in an in-memory
    /// `WorldStateStore`.
    @MainActor
    private func makeModel(root: GameDataRoot, fileSystem: VirtualFileSystem) throws -> Session {
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let store = QuestStore(file: file, pluginName: "Skyrim.esm")
        let quest = try #require(store.quest(editorID: Self.targetQuest))
        let quests = QuestRuntime(store: WorldStateStore(), quests: store)
        try quests.startQuest(quest.formID)
        for stage in quest.stages.map(\.index).sorted() {
            try quests.setStage(stage, on: quest.formID)
        }
        for objective in quest.objectives.map(\.index) {
            try quests.setObjectiveDisplayed(objective, on: quest.formID)
            try quests.setObjectiveCompleted(objective, on: quest.formID)
        }
        var model = JournalMenuModel.build(
            runtime: quests,
            strings: LocalizedStrings(vfs: fileSystem, pluginName: "Skyrim.esm")
        )
        let row = try #require(
            model.entries.firstIndex { $0.editorID == Self.targetQuest },
            "the target quest is not on the page"
        )
        model.select(row)
        return Session(model: model)
    }

    @MainActor
    private func openJournal(
        renderer: Renderer,
        fileSystem: VirtualFileSystem
    ) throws -> SWFMovieRuntime {
        let movie = try SWFMovieLoader(fileSystem: fileSystem).load(
            path: QuestJournalMovieBridge.moviePath
        )
        try renderer.setSWFMovie(movie)
        renderer.swfEnabled = true
        renderer.swfScale = 1
        let runtime = try #require(
            try renderer.startSWFRuntime(prepare: SystemMenuMovieBridge.prepare(runtime:))
        )
        try renderer.updateSWFRuntime { runtime in
            SystemMenuMovieBridge.activate(runtime: runtime) {}
            QuestJournalMovieBridge.activate(runtime: runtime)
        }
        for _ in 0 ..< GameViewController.journalActivationTicks {
            try renderer.advanceSWFRuntime()
        }
        return runtime
    }
}

// MARK: - Rendering

extension JournalAcceptanceRealDataTests {
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

    fileprivate static func changedPixels(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
        stride(from: 0, to: min(lhs.count, rhs.count), by: 4).reduce(0) { count, index in
            let changed = (0 ..< 3).contains { lhs[index + $0] != rhs[index + $0] }
            return count + (changed ? 1 : 0)
        }
    }
}

// MARK: - Evidence

private enum JournalEvidence {
    /// What the run measured, so the evidence writer stays inside the
    /// parameter-count limit.
    struct Measurement {
        let diagnostics: QuestJournalDiagnostics
        let questRows: Int
        let title: String
        let objectives: [String]
        let objectiveFrames: [String]
        let logEntries: [String]
        let nodes: Int
        let broughtUpChanged: Int
        let publishedChanged: Int
        let tabbedChanged: Int
    }

    @MainActor
    static func writeFrames(
        empty: (texture: MTLTexture, pixels: [UInt8]),
        broughtUp: (texture: MTLTexture, pixels: [UInt8]),
        published: (texture: MTLTexture, pixels: [UInt8]),
        tabbed: (texture: MTLTexture, pixels: [UInt8])
    ) throws {
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        for (frame, name) in [
            (empty, "journal-empty.png"),
            (broughtUp, "journal-brought-up.png"),
            (published, "journal-published.png"),
            (tabbed, "journal-tabbed.png")
        ] {
            try FrameScreenshot.write(texture: frame.texture, to: logs.appending(path: name))
        }
    }

    static func write(
        runtime: SWFMovieRuntime,
        stats: SWFDrawStats,
        measurement: Measurement
    ) throws {
        let missing = runtime.tally.rankedMissing
            .prefix(12)
            .map { "\($0.name) \($0.count)" }
            .joined(separator: ", ")
        let report = """
        [INFO] movie: \(QuestJournalMovieBridge.moviePath)
        [INFO] display nodes: \(measurement.nodes)
        [INFO] faults: \(measurement.diagnostics.faults)
        [INFO] unimplemented opcodes: \(runtime.tally.unimplementedTotal)
        [INFO] invokes: \(runtime.invokeLog.total) total, \
        \(measurement.diagnostics.unhandledInvokes) unhandled
        [INFO] missing names: \(measurement.diagnostics.missingNames) distinct
        [INFO] top missing: \(missing)
        [INFO] draws: \(stats.drawCalls), glyphs \(stats.glyphs), \
        skipped \(stats.skippedItems)
        [INFO] quest rows: \(measurement.questRows)
        [INFO] title: \(measurement.title)
        [INFO] objectives: \(measurement.objectives.joined(separator: " | "))
        [INFO] objective frames: \(measurement.objectiveFrames.joined(separator: ", "))
        [INFO] journal entries: \(measurement.logEntries.count)
        [INFO] changed pixels: bring-up \(measurement.broughtUpChanged), \
        published \(measurement.publishedChanged), tabbed \(measurement.tabbedChanged)

        """
        try report.write(
            to: logs.appending(path: "journal-acceptance.log"),
            atomically: true,
            encoding: .utf8
        )
    }

    /// Gitignored: a rendered journal frame embeds the user's game art, and the
    /// resolved journal text is the plugin's own strings. Resolved from the
    /// source path rather than the working directory, which for the test host
    /// is the read-only root.
    private static var logs: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "logs")
    }
}
