// The running tour's readout over the game view. It is an AppKit view, not a
// render pass, so it costs no GPU time and never shows in a capture.

import AppKit
import OpenSkyWorld

@MainActor
final class BenchmarkOverlayView: NSView {
    private let label = NSTextField(labelWithString: "")

    /// The toolbar toggle writes this; a hidden overlay keeps the tour running.
    var isOverlayEnabled = true {
        didSet { isHidden = !isOverlayEnabled }
    }

    var readout: String {
        label.stringValue
    }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 64))
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        layer?.cornerRadius = 6
        label.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.maximumNumberOfLines = 3
        label.setAccessibilityIdentifier("BenchmarkOverlayLabel")
        setAccessibilityIdentifier("BenchmarkOverlay")
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func attach(to host: NSView) {
        guard superview !== host else { return }
        removeFromSuperview()
        translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(self)
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 16),
            topAnchor.constraint(equalTo: host.topAnchor, constant: 16)
        ])
        isHidden = !isOverlayEnabled
        label.stringValue = "Benchmark starting"
    }

    func detach() {
        removeFromSuperview()
    }

    func show(_ snapshot: BenchmarkTourSnapshot?) {
        guard let snapshot else { return }
        label.stringValue = Self.text(for: snapshot)
    }

    static func text(for snapshot: BenchmarkTourSnapshot) -> String {
        let fps = snapshot.fps.map { String(format: "%.0f fps", $0) } ?? "- fps"
        let step = switch snapshot.step {
        case .loading: "Timing cold and warm loads"
        case .arriving: "Travelling"
        case .settling: "Warming up"
        case .measuring: "Measuring"
        }
        let percent = Int((snapshot.progress * 100).rounded())
        return "Scene \(snapshot.sceneNumber) of \(snapshot.sceneCount): \(snapshot.title)\n"
            + "\(step) \(percent)%\n\(fps)"
    }
}
