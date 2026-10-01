// The app's screenshot path: GameViewController loads its renderer through the
// production wiring, with the shaders of the app bundle, and writes one frame
// as a PNG. Skips without a Metal 4 device (paravirtual CI).

import AppKit
import Foundation
import Metal
@testable import OpenSky
import TagsTesting
import Testing

@Suite(.tags(.gpu))
struct GameViewControllerScreenshotTests {
    private static var hasMetal4Device: Bool {
        MTLCreateSystemDefaultDevice()?.supportsFamily(.metal4) ?? false
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func appWorldWritesScreenshot() throws {
        let controller = GameViewController()
        _ = controller.view // load renderer through production app wiring
        let url = FileManager.default.temporaryDirectory
            .appending(path: "opensky-app-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }

        try controller.writeScreenshot(to: url)

        let data = try Data(contentsOf: url)
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        #expect(data.count > 1024)
    }
}
