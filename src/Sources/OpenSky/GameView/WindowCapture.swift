// Saves the next frame the game window presents, without app chrome.

import Foundation
import OpenSkyRendering
import OpenSkyRenderResources

enum WindowCapture {
    enum CaptureError: LocalizedError {
        case rendererNotReady
        case noWindowFrame

        var errorDescription: String? {
            switch self {
            case .rendererNotReady: "World renderer is not ready for a screenshot."
            case .noWindowFrame: "The game window presented no frame to capture."
            }
        }
    }

    /// Gives up after 60 drawn frames with no copy, or 10 s: a hidden window encodes
    /// none. A busy main actor draws few frames a second, and an encoded copy waits
    /// for a busy GPU until the 10 s end.
    static func write(from renderer: Renderer?, to url: URL) async throws {
        guard let renderer else { throw CaptureError.rendererNotReady }
        renderer.requestWindowCapture()
        let firstFrame = renderer.frameIndex
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(10)
        while clock.now < deadline {
            if let texture = renderer.takeWindowCapture() {
                try FrameScreenshot.write(texture: texture, to: url)
                return
            }
            if !renderer.hasEncodedWindowCapture, renderer.frameIndex - firstFrame >= 60 {
                break
            }
            try await Task.sleep(for: .milliseconds(8))
        }
        throw CaptureError.noWindowFrame
    }
}
