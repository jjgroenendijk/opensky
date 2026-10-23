// The overlay toggle and the stop button of a running benchmark tour. The game
// window gets a toolbar with only these two for the length of a run.

import AppKit

@MainActor
final class BenchmarkToolbarItems: NSObject {
    static let overlayID = NSToolbarItem.Identifier("BenchmarkOverlay")
    static let stopID = NSToolbarItem.Identifier("BenchmarkStop")

    weak var benchmark: BenchmarkWorldAdapter? {
        didSet { refresh() }
    }

    let overlayButton = NSButton(
        image: NSImage(
            systemSymbolName: "speedometer",
            accessibilityDescription: "Benchmark overlay"
        )
            ?? NSImage(),
        target: nil,
        action: nil
    )
    let stopButton = NSButton(
        image: NSImage(systemSymbolName: "stop.circle", accessibilityDescription: "Stop benchmark")
            ?? NSImage(),
        target: nil,
        action: nil
    )

    override init() {
        super.init()
        overlayButton.setButtonType(.pushOnPushOff)
        overlayButton.bezelStyle = .toolbar
        overlayButton.target = self
        overlayButton.action = #selector(toggleOverlay)
        overlayButton.toolTip = "Show or hide the benchmark readout"
        overlayButton.setAccessibilityIdentifier("BenchmarkOverlayButton")
        stopButton.bezelStyle = .toolbar
        stopButton.target = self
        stopButton.action = #selector(stopTour)
        stopButton.toolTip = "Stop the benchmark and keep the scenes measured so far"
        stopButton.setAccessibilityIdentifier("BenchmarkStopButton")
        refresh()
    }

    func item(for identifier: NSToolbarItem.Identifier) -> NSToolbarItem? {
        let button: NSButton
        let label: String
        switch identifier {
        case Self.overlayID: (button, label) = (overlayButton, "Benchmark Overlay")
        case Self.stopID: (button, label) = (stopButton, "Stop Benchmark")
        default: return nil
        }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.view = button
        item.label = label
        item.paletteLabel = label
        return item
    }

    /// The Play window's toolbar during a run.
    func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "BenchmarkToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        return toolbar
    }

    func refresh() {
        let running = benchmark?.isRunning ?? false
        overlayButton.isEnabled = running
        stopButton.isEnabled = running
        overlayButton.state = (benchmark?.overlay.isOverlayEnabled ?? false) && running ? .on : .off
    }

    @objc private func toggleOverlay() {
        guard let benchmark else { return }
        benchmark.overlay.isOverlayEnabled = overlayButton.state == .on
    }

    @objc private func stopTour() {
        benchmark?.stop()
    }
}

extension BenchmarkToolbarItems: NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.overlayID, Self.stopID]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar _: Bool
    ) -> NSToolbarItem? {
        item(for: itemIdentifier)
    }
}
