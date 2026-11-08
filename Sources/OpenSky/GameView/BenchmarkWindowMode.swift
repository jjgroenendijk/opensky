// The game window during a tour: hidden, a fixed-size window, or full screen,
// and back as it was afterwards (docs/tools/benchmark.md, While it runs).

import AppKit
import MetalKit
import OpenSkyWorld
import OpenSkyWorldInterface

final class BenchmarkWindowMode {
    private var window: NSWindow?
    private var orderedOut = false
    private var enteredFullScreen = false
    private var savedFrame: NSRect?
    /// Keeps App Nap from slowing the frame loop while the app is in the background.
    private var activity: (any NSObjectProtocol)?

    func apply(_ request: BenchmarkRequest, window: NSWindow?, view: NSView) {
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical, .idleSystemSleepDisabled],
            reason: "OpenSky benchmark tour"
        )
        guard let window else { return }
        self.window = window
        switch request.display {
        case .fullScreen:
            if !window.styleMask.contains(.fullScreen) {
                enteredFullScreen = true
                window.toggleFullScreen(nil)
            }
        case .hidden:
            // A window that was never shown stays so; the view's own loop still draws.
            if window.isVisible {
                orderedOut = true
                window.orderOut(nil)
            }
        case .windowed:
            break
        }
        if let size = request.effectiveFrameSize, !window.styleMask.contains(.fullScreen) {
            resize(window, view: view, to: size)
        }
    }

    func restore() {
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
        }
        activity = nil
        defer {
            window = nil
            orderedOut = false
            enteredFullScreen = false
            savedFrame = nil
        }
        guard let window else { return }
        if let savedFrame {
            window.setFrame(savedFrame, display: false)
        }
        if enteredFullScreen, window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
        if orderedOut {
            window.orderFront(nil)
        }
    }

    private func resize(_ window: NSWindow, view: NSView, to size: BenchmarkFrameSize) {
        savedFrame = window.frame
        let scale = max(window.backingScaleFactor, 1)
        let points = NSSize(
            width: CGFloat(size.width) / scale,
            height: CGFloat(size.height) / scale
        )
        window.setContentSize(points)
        // A window off the screen may skip layout, so the drawable is set directly.
        (view as? MTKView)?.drawableSize = CGSize(width: size.width, height: size.height)
    }
}
