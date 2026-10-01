// M13 acceptance, pixel half: advancing a stage adds a journal paragraph. The
// advanced page must also be byte-identical to a page built at that stage
// directly. Needs Metal 4 and the install; frames go to gitignored `logs/`.

import Foundation
import Metal
import MetalKit
@testable import OpenSky
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsSWF
@testable import OpenSkyGameData
@testable import OpenSkyMenus
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import Testing

struct QuestAcceptanceRenderTests {
    private static let width = 1280
    private static let height = 720

    /// How many pixels the advance has to move before it counts as visible.
    /// Well above the handful a rounding difference could touch and far below
    /// a paragraph's worth of glyphs, so the number is a floor rather than a
    /// tuned value.
    private static let minimumChangedPixels = 200

    @Test(.enabled(if: RealDataEnvironment.canRender)) @MainActor
    func advancingAStageDrawsANewJournalParagraph() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let device = try #require(RealDataEnvironment.device)
        let fileSystem = VirtualFileSystem(root: root)
        let renderer = try Self.makeRenderer(device: device)
        let runtime = try JournalMovieFixture.open(renderer: renderer, fileSystem: fileSystem)

        let walked = try QuestAcceptanceRenderWalk(root: root, fileSystem: fileSystem)
        let early = try Self.publish(walked.earlyPage, renderer: renderer)
        #expect(walked.earlyPage.selectedEntry?.logEntries.count == 1)

        let advanced = try Self.publish(walked.advancedPage, renderer: renderer)
        #expect(walked.advancedPage.selectedEntry?.logEntries.count == 2)
        let grew = Self.changedPixels(early.pixels, advanced.pixels)
        #expect(
            grew >= Self.minimumChangedPixels,
            "the new journal paragraph changed only \(grew) pixels"
        )

        // The cross-check: a session that walked straight to the later stage
        // draws the identical page, so the delta above is the paragraph and not
        // the republish.
        let direct = try Self.publish(walked.directPage, renderer: renderer)
        #expect(walked.directPage == walked.advancedPage)
        #expect(Self.changedPixels(advanced.pixels, direct.pixels) == 0)

        // The page that drew is the page the engine holds, and it drew cleanly.
        #expect(
            QuestJournalMovieBridge.titleText(runtime: runtime)
                == walked.advancedPage.selectedEntry?.title
        )
        #expect(QuestJournalMovieBridge.diagnostics(runtime: runtime).faults == 0)
        #expect(renderer.lastSWFDrawStats.drawCalls > 0, "the journal drew nothing")

        try Self.writeFrames(early: early, advanced: advanced, direct: direct, changed: grew)
    }

    // MARK: - Publishing

    /// Pushes one page through the measured `quest_journal.swf` contract and
    /// renders the frame it produced.
    @MainActor
    private static func publish(
        _ model: JournalMenuModel,
        renderer: Renderer
    ) throws -> (texture: MTLTexture, pixels: [UInt8]) {
        try renderer.updateSWFRuntime { runtime in
            QuestJournalMovieBridge.publish(model, runtime: runtime)
        }
        try renderer.advanceSWFRuntime()
        return try render(renderer)
    }

    // MARK: - Rendering

    @MainActor
    private static func makeRenderer(device: MTLDevice) throws -> Renderer {
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: width, height: height), device: device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        return try Renderer(view: view)
    }

    @MainActor
    private static func render(
        _ renderer: Renderer
    ) throws -> (texture: MTLTexture, pixels: [UInt8]) {
        let texture = try renderer.renderOffscreen(
            width: width, height: height, animationTime: 1
        )
        return (texture, RenderedPixels.read(texture))
    }

    private static func changedPixels(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
        guard lhs.count == rhs.count else { return max(lhs.count, rhs.count) / 4 }
        return stride(from: 0, to: lhs.count, by: 4).reduce(0) { count, index in
            let changed = (0 ..< 3).contains { lhs[index + $0] != rhs[index + $0] }
            return count + (changed ? 1 : 0)
        }
    }

    // MARK: - Evidence

    /// Gitignored, and linked from the pull request rather than committed.
    @MainActor
    private static func writeFrames(
        early: (texture: MTLTexture, pixels: [UInt8]),
        advanced: (texture: MTLTexture, pixels: [UInt8]),
        direct: (texture: MTLTexture, pixels: [UInt8]),
        changed: Int
    ) throws {
        let logs = try RepositoryLogs.directory()
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        for (frame, name) in [
            (early, "m13-journal-early.png"),
            (advanced, "m13-journal-advanced.png"),
            (direct, "m13-journal-direct.png")
        ] {
            try FrameScreenshot.write(texture: frame.texture, to: logs.appending(path: name))
        }
        try "[INFO] changed pixels on the stage advance: \(changed)\n".write(
            to: logs.appending(path: "m13-journal-render.log"),
            atomically: true,
            encoding: .utf8
        )
    }
}

/// The three pages the render gate compares, built off the real install: the
/// quest at its first journal stage, the same session one stage later, and a
/// second session walked straight to that later stage.
@MainActor
struct QuestAcceptanceRenderWalk {
    let earlyPage: JournalMenuModel
    let advancedPage: JournalMenuModel
    let directPage: JournalMenuModel

    init(root: GameDataRoot, fileSystem _: VirtualFileSystem) throws {
        let editorID = "MGRArniel01"
        let session = try QuestRealDataSession(root: root, pluginName: "Skyrim.esm")
        let quest = try #require(session.quests.quest(editorID: editorID))
        let key = try #require(session.quests.key(for: quest.formID))
        let stages = Set(quest.stages.map(\.index)).sorted()
        let first = try #require(stages.first)
        let last = try #require(stages.last)
        #expect(stages.count == 2, "the target quest no longer has exactly two stages")

        try session.start(quest: quest, key: key, upTo: first)
        earlyPage = try Self.page(session, editorID: editorID)
        try session.advance(to: last, key: key)
        advancedPage = try Self.page(session, editorID: editorID)

        let straight = try QuestRealDataSession(root: root, pluginName: "Skyrim.esm")
        try straight.start(quest: quest, key: key, upTo: last)
        directPage = try Self.page(straight, editorID: editorID)
    }

    private static func page(
        _ session: QuestRealDataSession,
        editorID: String
    ) throws -> JournalMenuModel {
        var model = try session.journal()
        let row = try #require(
            model.entries.firstIndex { $0.editorID == editorID },
            "the target quest is not on the journal page"
        )
        model.select(row)
        return model
    }
}
