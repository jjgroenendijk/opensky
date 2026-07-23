// Inspector-panel protocol + the 2 Hz readout ticker shared by every main-app
// destination panel (issue #98). Formerly WorldInspectorPanel + a Timer field
// duplicated in each panel; centralized so start/stop lifecycle is written once.

import AppKit

/// A destination controls panel the shell can start/stop as it is revealed or
/// the containing view leaves screen. Sections and full panels both conform.
@MainActor
protocol InspectorPanel: NSViewController {
    func startInspecting()
    func stopInspecting()
}

/// A repeating 2 Hz driver for live readouts. Added to the common run-loop mode
/// so the readout keeps ticking during menu/resize tracking. Idempotent start.
@MainActor
final class InspectionTicker {
    private var timer: Timer?
    private var onTick: (() -> Void)?

    /// True while a repeating timer is scheduled.
    var isActive: Bool {
        timer != nil
    }

    /// Starts ticking (no-op if already running).
    func start(onTick: @escaping () -> Void) {
        self.onTick = onTick
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.onTick?() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Stops ticking.
    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
