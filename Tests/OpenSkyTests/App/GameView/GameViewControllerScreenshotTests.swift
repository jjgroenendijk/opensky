// The app's screenshot path: GameViewController loads its renderer through the
// production wiring, with the shaders of the app bundle, and writes the next
// frame its window presents as a PNG. Skips without a Metal 4 device
// (paravirtual CI).

import AppKit
import Foundation
import Metal
import MetalKit
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
    func appWorldWritesTheWindowFrame() async throws {
        let controller = GameViewController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentViewController = controller // production renderer wiring
        let view = try #require(controller.view as? MTKView)
        let url = FileManager.default.temporaryDirectory
            .appending(path: "opensky-app-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }

        let save = Task { try await controller.writeScreenshot(to: url) }
        for _ in 0 ..< 10 {
            try await Task.sleep(for: .milliseconds(20))
            view.draw()
        }
        try await save.value

        let data = try Data(contentsOf: url)
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        #expect(data.count > 1024)
    }
}
