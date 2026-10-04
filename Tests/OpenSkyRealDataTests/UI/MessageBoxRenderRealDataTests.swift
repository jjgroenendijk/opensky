// A vanilla yes/no message box, built from its MESG and drawn by the box
// overlay with each button highlighted in turn. Frames and the report go to
// `logs/message-box/`.
// Run with `make test-real T='MessageBoxRenderRealDataTests'`.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyMenus
@testable import OpenSkyRendering
import TagsTesting
import Testing

@Suite(.tags(.gpu))
struct MessageBoxRenderRealDataTests {
    private static let width = 1280
    private static let height = 720

    @Test(.enabled(if: RealDataEnvironment.canRender))
    @MainActor
    func aVanillaQuestionDrawsWithEachAnswerHighlighted() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let device = try #require(RealDataEnvironment.device)
        let plugins = try VanillaMasters.load(root: root)
        let store = PresentationRecordStore(plugins: plugins)
        let strings = LocalizedStrings(vfs: VirtualFileSystem(root: root), pluginName: "Skyrim.esm")
        let builder = MessageTextBuilder(strings: strings)
        let question = try #require(store.messages.records
            .filter {
                $0.sourcePlugin == "Skyrim.esm" && $0.record.isMessageBox && $0.record.buttons
                    .count == 2
            }
            .map { (editorID: $0.record.editorID ?? "?", built: builder.build($0.record)) }
            .filter { !$0.built.text.isEmpty && $0.built.buttons.allSatisfy { !$0.text.isEmpty } }
            .min { $0.editorID < $1.editorID })
        let request = MessageBoxRequest(
            title: question.built.title, text: question.built.text, buttons: question.built.buttons,
            token: 1
        )
        let renderer = try RenderedPixels.offscreenRenderer(
            device: device,
            width: Self.width,
            height: Self.height
        )
        let logs = try RepositoryLogs.directory().appending(path: "message-box")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        var frames: [[UInt8]] = []
        for selection in 0 ..< 2 {
            renderer.uiScene = MessageBoxPresentation(request: request, selection: selection).scene
            let frame = try RenderedPixels.renderFrame(
                renderer,
                width: Self.width,
                height: Self.height
            )
            try FrameScreenshot.write(
                texture: frame.texture,
                to: logs.appending(path: "selection-\(selection).png")
            )
            frames.append(frame.pixels)
        }
        var model = MessageBoxMenuModel()
        model.enqueue(request)
        model.moveSelection(by: 1)
        let answer = model.accept()
        let lines = [
            "[INFO] \(question.editorID): \(question.built.buttons.map(\.text))",
            "[INFO] text: \(question.built.text.prefix(120))",
            "[INFO] second row picked answers button \(answer?.buttonIndex ?? -1) "
                + "to token \(answer?.token ?? 0)",
            "[INFO] pixels that differ between the two highlights: "
                + "\(RenderedPixels.changedCount(frames[0], frames[1]))"
        ]
        try lines.joined(separator: "\n").write(
            to: logs.appending(path: "report.log"),
            atomically: true,
            encoding: .utf8
        )
        #expect(answer == MessageBoxAnswer(token: 1, buttonIndex: question.built.buttons[1].index))
        #expect(RenderedPixels.changedCount(frames[0], frames[1]) > 0, "\(lines)")
    }
}
