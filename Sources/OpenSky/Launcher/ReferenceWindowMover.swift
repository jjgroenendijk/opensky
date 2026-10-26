// Wine ignores `iLocation X/Y` in SkyrimPrefs.ini, so the Windows game's window moves
// through the Accessibility API once it is on screen. Moving another app's window needs
// the Accessibility permission for OpenSky.

import ApplicationServices
import Foundation
import OpenSkyReference

enum ReferenceMoveError: Error, LocalizedError {
    case noWindow

    var errorDescription: String? {
        "The Windows game window did not appear. Check Steam, then start it again."
    }
}

@MainActor
enum ReferenceWindowMover {
    /// Moves every window of the game's process; false when none moved or access is missing.
    static func move(pid: pid_t, to frame: ReferenceWindowFrame) -> Bool {
        // The value of `kAXTrustedCheckOptionPrompt`, a global var Swift 6 refuses to read.
        guard AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        else { return false }
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        // The values of `kAXWindowsAttribute` and `kAXPositionAttribute`.
        guard
            AXUIElementCopyAttributeValue(app, "AXWindows" as CFString, &value) == .success,
            let windows = value as? [AXUIElement]
        else { return false }
        var origin = CGPoint(x: frame.x, y: frame.y)
        guard let position = AXValueCreate(.cgPoint, &origin) else { return false }
        var moved = false
        for window in windows {
            let result = AXUIElementSetAttributeValue(window, "AXPosition" as CFString, position)
            moved = moved || result == .success
        }
        return moved
    }
}
