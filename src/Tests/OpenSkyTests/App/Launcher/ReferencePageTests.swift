// The Reference Game page without a prefix, and the comparison view's three modes on a
// synthetic run folder.

import AppKit
import Foundation
@testable import OpenSky
import OpenSkyReference
import OpenSkyRenderResources
import Testing

@MainActor
struct ReferencePageTests {
    @Test func withoutAPrefixThePageSaysHowToSetOneUp() {
        let page = ReferencePageViewController(context: LauncherContext(actions: nil))
        page.loadViewIfNeeded()
        #expect(page.prefixLabel.stringValue == ReferencePrefixStatus.notSet.message)
    }

    @Test func aRunWithBothCapturesShowsAndSwitchesModes() throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "reference-page-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let run = ReferenceComparisonRun(directory: folder)
        let pixel = TexturePixels(width: 1, height: 1, rgba: [9, 9, 9, 255])
        for url in [run.openskyImage, run.referenceImage, run.differenceImage] {
            try FrameScreenshot.write(image: #require(pixel.cgImage()), to: url)
        }

        let view = ReferenceComparisonView(width: 540)
        view.load(run)
        #expect(!view.isHidden)
        view.select(.difference)
        #expect(view.state.images == [ReferenceComparisonImage.difference])
    }
}
