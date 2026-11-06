// Draws the game view as fast as the GPU allows, for the benchmark tour. The
// view's own timer paces to the display and caps a run at its refresh rate.

import MetalKit
import QuartzCore

@MainActor
final class UnlimitedFrameLoop {
    /// Far below any frame time, so the timer never holds a frame back.
    private static let interval: TimeInterval = 0.001

    private weak var view: MTKView?
    private var timer: Timer?

    /// Takes over the view's draw loop until `stop()`.
    func start(_ view: MTKView) {
        guard timer == nil else { return }
        self.view = view
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        (view.layer as? CAMetalLayer)?.displaySyncEnabled = false
        // A run loop timer, not a chain of queued blocks: between frames the run loop
        // still serves the main queue, where scaler builds and other tasks finish.
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.view?.draw()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Gives the draw loop back to the view's timer.
    func stop() {
        guard let timer else { return }
        timer.invalidate()
        self.timer = nil
        guard let view else { return }
        (view.layer as? CAMetalLayer)?.displaySyncEnabled = true
        view.isPaused = false
    }
}
