// Draws the game view as fast as the GPU allows, for the benchmark tour. The
// view's own timer paces to the display and caps a run at its refresh rate.

import MetalKit
import QuartzCore

@MainActor
final class UnlimitedFrameLoop {
    private weak var view: MTKView?
    private var isRunning = false

    /// Takes over the view's draw loop until `stop()`.
    func start(_ view: MTKView) {
        guard !isRunning else { return }
        self.view = view
        isRunning = true
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        (view.layer as? CAMetalLayer)?.displaySyncEnabled = false
        scheduleNextFrame()
    }

    /// Gives the draw loop back to the view's timer.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        guard let view else { return }
        (view.layer as? CAMetalLayer)?.displaySyncEnabled = true
        view.isPaused = false
    }

    private func drawAndContinue() {
        guard isRunning, let view else { return }
        view.draw()
        scheduleNextFrame()
    }

    /// One frame per run loop pass, so input, timers, and agent commands still run between frames.
    private func scheduleNextFrame() {
        RunLoop.main.perform(inModes: [.common]) { [weak self] in
            MainActor.assumeIsolated {
                self?.drawAndContinue()
            }
        }
        // A queued block alone does not wake a sleeping run loop.
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }
}
