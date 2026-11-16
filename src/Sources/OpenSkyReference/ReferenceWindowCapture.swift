// Captures the reference game's window with `screencapture -l`, which takes one window
// without its shadow, even when another window covers it or it is on another Space. It
// needs the Screen Recording permission for the app or terminal that asks.

import CoreGraphics
public import Foundation

nonisolated public enum ReferenceCaptureError: Error, Equatable, Sendable, LocalizedError {
    case noWindow
    case captureFailed(UInt32)
    case encodeFailed(String)
    case openSkyFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noWindow: "No reference game window is open. Start the reference game first."
        case let .captureFailed(id):
            "screencapture could not capture window \(id). Check the Screen Recording permission."
        case let .encodeFailed(name): "Cannot encode \(name)."
        case let .openSkyFailed(message): "The OpenSky capture failed: \(message)"
        }
    }
}

nonisolated public enum ReferenceWindowCapture {
    /// Every window the window server knows, on any Space, because the game window is often
    /// on a Space other than the one in front.
    public static func allWindows() -> [ReferenceWindowInfo] {
        let info = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], 0)
            as? [[String: Any]] ?? []
        return info.compactMap { entry -> ReferenceWindowInfo? in
            guard
                let id = entry[kCGWindowNumber as String] as? UInt32,
                let owner = entry[kCGWindowOwnerName as String] as? String,
                let layer = entry[kCGWindowLayer as String] as? Int,
                let bounds = entry[kCGWindowBounds as String] as? [String: Double]
            else { return nil }
            return ReferenceWindowInfo(
                id: id, ownerName: owner, layer: layer,
                width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0,
                x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0,
                ownerPID: entry[kCGWindowOwnerPID as String] as? Int32 ?? 0,
                isOnScreen: entry[kCGWindowIsOnscreen as String] as? Bool ?? false
            )
        }
    }

    /// The reference game's window now; `expected` prefers the window of that size.
    public static func window(expected: ReferenceWindowFrame?) -> ReferenceWindowInfo? {
        ReferenceWindow.pick(allWindows(), expected: expected)
    }

    /// Writes the reference window as a PNG; `expected` prefers the window of that size.
    public static func capture(to url: URL, expected: ReferenceWindowFrame?) throws {
        guard let window = window(expected: expected) else {
            throw ReferenceCaptureError.noWindow
        }
        let tool = Process()
        tool.executableURL = URL(filePath: "/usr/sbin/screencapture")
        tool.arguments = ["-x", "-o", "-l\(window.id)", url.path(percentEncoded: false)]
        try tool.run()
        tool.waitUntilExit()
        guard
            tool.terminationStatus == 0,
            FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
        else {
            throw ReferenceCaptureError.captureFailed(window.id)
        }
    }
}
