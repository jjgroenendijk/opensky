// Main app content: one window with an in-place World / Asset Browser mode
// switch. The browser stays alive across mode changes so its loaded catalog,
// filter, selection, and renderer caches survive a round trip through World.

import AppKit
import UniformTypeIdentifiers

final class MainViewController: NSViewController {
    private enum Mode: Int {
        case world
        case assetBrowser
    }

    private var worldViewController: GameViewController
    /// World mode is presented through its sidebar shell (destinations +
    /// controls) rather than the bare game view; rebuilt on a Settings reload.
    private var worldContainer: WorldSidebarViewController
    private let browserViewController: PreviewViewController
    private var visibleViewController: NSViewController?

    private let modeControl = NSSegmentedControl(
        labels: ["World", "Asset Browser"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let screenshotButton = NSButton(
        title: "Screenshot…",
        target: nil,
        action: nil
    )
    private let contentView = NSView()

    init(
        worldViewController: GameViewController,
        browserViewController: PreviewViewController
    ) {
        self.worldViewController = worldViewController
        worldContainer = WorldSidebarViewController(gameViewController: worldViewController)
        self.browserViewController = browserViewController
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800))
        modeControl.target = self
        modeControl.action = #selector(modeChanged)
        modeControl.selectedSegment = Mode.world.rawValue
        modeControl.setAccessibilityIdentifier("ModeSwitcher")
        modeControl.translatesAutoresizingMaskIntoConstraints = false
        screenshotButton.target = self
        screenshotButton.action = #selector(saveScreenshot)
        screenshotButton.toolTip = "Save the current World camera as a PNG"
        screenshotButton.setAccessibilityIdentifier("ScreenshotButton")
        screenshotButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(modeControl)
        root.addSubview(screenshotButton)
        root.addSubview(contentView)
        NSLayoutConstraint.activate([
            modeControl.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
            modeControl.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            screenshotButton.centerYAnchor.constraint(equalTo: modeControl.centerYAnchor),
            screenshotButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            contentView.topAnchor.constraint(equalTo: modeControl.bottomAnchor, constant: 8),
            contentView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        show(worldContainer)
    }

    /// Applies a Settings change without relaunch. Replacing World creates a
    /// fresh renderer + streamer over the new root; browser reload preserves
    /// the controller while dropping stale async catalog/filter work.
    func reload(
        worldViewController: GameViewController,
        browserRoot: GameDataRoot?,
        errorMessage: String?
    ) {
        let worldWasVisible = visibleViewController === worldContainer
        if !worldWasVisible {
            worldContainer.removeFromParent()
        }
        self.worldViewController = worldViewController
        worldContainer = WorldSidebarViewController(gameViewController: worldViewController)
        browserViewController.reload(root: browserRoot, errorMessage: errorMessage)
        if worldWasVisible {
            show(worldContainer)
        }
    }

    @objc private func modeChanged() {
        let mode = Mode(rawValue: modeControl.selectedSegment) ?? .world
        switch mode {
        case .world:
            show(worldContainer)
        case .assetBrowser:
            show(browserViewController)
        }
    }

    @objc private func saveScreenshot() {
        guard
            visibleViewController === worldContainer,
            let window = view.window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = Self.defaultScreenshotName()
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            do {
                try worldViewController.writeScreenshot(to: url)
                showSavedState()
            } catch {
                showScreenshotError(error)
            }
        }
    }

    private static func defaultScreenshotName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "OpenSky-\(formatter.string(from: Date())).png"
    }

    private func showSavedState() {
        screenshotButton.title = "Saved"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.screenshotButton.title = "Screenshot…"
        }
    }

    private func showScreenshotError(_ error: Error) {
        let alert = NSAlert(error: error)
        if let window = view.window {
            alert.beginSheetModal(for: window)
        }
    }

    private func show(_ controller: NSViewController) {
        guard visibleViewController !== controller else { return }
        visibleViewController?.view.removeFromSuperview()
        visibleViewController?.removeFromParent()
        addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.topAnchor.constraint(equalTo: contentView.topAnchor),
            controller.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            controller.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        visibleViewController = controller
        screenshotButton.isEnabled = controller === worldContainer
            && worldViewController.canWriteScreenshot
    }
}
