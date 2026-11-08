// The game view's side of a benchmark tour, so the tour adapter needs no AppKit.

import AppKit
import MetalKit
import OpenSkyAgentAdapters
import OpenSkyWorld
import OpenSkyWorldInterface

final class BenchmarkViewSurface: BenchmarkViewPort {
    private let view: NSView
    private let overlay = BenchmarkOverlayView()
    private let windowMode = BenchmarkWindowMode()
    /// The tour measures the engine, not the display, so it draws with no frame cap.
    private let frameLoop = UnlimitedFrameLoop()

    init(view: NSView) {
        self.view = view
    }

    var drawableSize: CGSize {
        (view as? MTKView)?.drawableSize ?? .zero
    }

    var isOverlayEnabled: Bool {
        get { overlay.isOverlayEnabled }
        set { overlay.isOverlayEnabled = newValue }
    }

    func attachOverlay(enabled: Bool) {
        overlay.isOverlayEnabled = enabled
        overlay.attach(to: view)
    }

    func showOverlay(_ snapshot: BenchmarkTourSnapshot?) {
        overlay.show(snapshot)
    }

    func detachOverlay() {
        overlay.detach()
    }

    func applyWindowMode(_ request: BenchmarkRequest) {
        unsafe windowMode.apply(request, window: view.window, view: view)
    }

    func restoreWindowMode() {
        windowMode.restore()
    }

    func startUncappedFrames() -> Bool {
        guard let view = view as? MTKView else { return false }
        frameLoop.start(view)
        return true
    }

    func stopUncappedFrames() {
        frameLoop.stop()
    }
}
