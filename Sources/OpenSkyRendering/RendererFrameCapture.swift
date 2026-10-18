// A Metal GPU trace of one live frame, for a benchmark scene. Metal records a
// trace only when the process starts with `MTL_CAPTURE_ENABLED=1`.

import Foundation
import Metal

nonisolated public enum FrameCaptureError: Error, Equatable, CustomStringConvertible {
    case notEnabled
    case failed(String)

    public var description: String {
        switch self {
        case .notEnabled:
            "GPU trace capture needs the app started with MTL_CAPTURE_ENABLED=1"
        case let .failed(message):
            "GPU trace capture failed: \(message)"
        }
    }
}

enum FrameCaptureState {
    case idle
    case requested(URL, (Result<URL, FrameCaptureError>) -> Void)
    case capturing(URL, (Result<URL, FrameCaptureError>) -> Void)
}

extension Renderer {
    public static var canCaptureGPUTrace: Bool {
        MTLCaptureManager.shared().supportsDestination(.gpuTraceDocument)
    }

    /// Writes the next drawn frame to `url`, a `.gputrace` path, then calls `done`.
    public func captureNextFrame(
        to url: URL, done: @escaping (Result<URL, FrameCaptureError>) -> Void
    ) {
        guard Self.canCaptureGPUTrace else {
            done(.failure(.notEnabled))
            return
        }
        frameCapture = .requested(url, done)
    }

    func beginFrameCapture() {
        guard case let .requested(url, done) = frameCapture else { return }
        let descriptor = MTLCaptureDescriptor()
        descriptor.captureObject = device
        descriptor.destination = .gpuTraceDocument
        descriptor.outputURL = url
        do {
            try MTLCaptureManager.shared().startCapture(with: descriptor)
            frameCapture = .capturing(url, done)
        } catch {
            frameCapture = .idle
            done(.failure(.failed(error.localizedDescription)))
        }
    }

    func endFrameCapture() {
        guard case let .capturing(url, done) = frameCapture else { return }
        MTLCaptureManager.shared().stopCapture()
        frameCapture = .idle
        done(.success(url))
    }
}
