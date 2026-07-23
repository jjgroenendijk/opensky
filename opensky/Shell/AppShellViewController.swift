// Unified-sidebar app shell (issue #98 PR 2): one NSSplitViewController for
// every destination — the segmented World/Asset Browser mode switch is gone.
// Sidebar rows come from DestinationRegistry; content is layered by
// ShellContentViewController so the game view never leaves the hierarchy.
// Full-content controllers (Asset Browser) are built lazily from their
// registry factory and cached forever, preserving catalog/filter/selection
// across destination changes and Settings reloads.

import AppKit

final class AppShellViewController: NSSplitViewController {
    private let sidebar = AppSidebarViewController()
    private let content: ShellContentViewController
    private let screenshotCoordinator = ScreenshotCoordinator()
    private let screenshotButton = NSButton(title: "Screenshot…", target: nil, action: nil)

    /// Lazily built full-content controllers, cached by destination id.
    private var fullContentControllers: [String: NSViewController] = [:]
    /// Data-root context handed to full-content factories; replaced on reload.
    private var fullContentContext: FullContentContext
    private var currentDestinationID: String?

    /// The embedded live World controller (screenshot + reload target).
    var gameViewController: GameViewController {
        content.gameViewController
    }

    init(gameViewController: GameViewController, fullContentContext: FullContentContext) {
        content = ShellContentViewController(gameViewController: gameViewController)
        self.fullContentContext = fullContentContext
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 280
        sidebarItem.canCollapse = true

        let contentItem = NSSplitViewItem(viewController: content)

        addSplitViewItem(sidebarItem)
        addSplitViewItem(contentItem)
        splitView.dividerStyle = .thin
        // Fresh autosave name: the shell changed shape in PR 2, stale widths
        // from the old World-only split must not apply.
        splitView.autosaveName = "AppShellSplit"

        sidebar.onSelect = { [weak self] descriptor in
            self?.show(descriptor)
        }
        // Default selection on launch: the plain live render.
        sidebar.select(id: DestinationRegistry.defaultDestinationID)
    }

    // MARK: - Destination routing

    private func show(_ descriptor: DestinationDescriptor) {
        currentDestinationID = descriptor.id
        switch descriptor.content {
        case .viewport:
            content.showViewport()
        case .worldInspector:
            content.showInspector(id: descriptor.id)
        case let .fullContent(makeController):
            let controller = fullContentControllers[descriptor.id]
                ?? makeController(fullContentContext)
            fullContentControllers[descriptor.id] = controller
            content.showFullContent(controller)
        }
        updateScreenshotButton()
    }

    // MARK: - Settings reload

    /// Applies a Settings change without relaunch, regardless of which
    /// destination is frontmost: swap the live game controller (fresh
    /// renderer + streamer over the new root), rebuild inspector panels,
    /// reload cached full-content controllers in place, re-apply selection.
    func reload(gameViewController: GameViewController, fullContentContext: FullContentContext) {
        self.fullContentContext = fullContentContext
        content.replaceGame(with: gameViewController)
        for controller in fullContentControllers.values {
            (controller as? any FullContentReloadable)?
                .reloadFullContent(context: fullContentContext)
        }
        if
            let id = currentDestinationID,
            let descriptor = DestinationRegistry.destination(id: id)
        {
            show(descriptor)
        }
        updateScreenshotButton()
    }

    // MARK: - Toolbar

    /// Builds the window toolbar (unifiedCompact): sidebar toggle, tracking
    /// separator, flexible space, screenshot.
    func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "AppShellToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        return toolbar
    }

    private enum ToolbarItemID {
        static let screenshot = NSToolbarItem.Identifier("Screenshot")
    }

    private func updateScreenshotButton() {
        let showsGameView = currentDestinationID
            .flatMap(DestinationRegistry.destination(id:))?.showsGameView ?? false
        screenshotButton.isEnabled = showsGameView && gameViewController.canWriteScreenshot
    }

    @objc private func saveScreenshot() {
        guard screenshotButton.isEnabled, let window = view.window else { return }
        screenshotCoordinator.saveScreenshot(
            from: gameViewController,
            window: window,
            button: screenshotButton
        )
    }
}

extension AppShellViewController: NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace, ToolbarItemID.screenshot]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar _: Bool
    ) -> NSToolbarItem? {
        guard itemIdentifier == ToolbarItemID.screenshot else { return nil }
        screenshotButton.bezelStyle = .toolbar
        screenshotButton.target = self
        screenshotButton.action = #selector(saveScreenshot)
        screenshotButton.toolTip = "Save the current World camera as a PNG"
        screenshotButton.setAccessibilityIdentifier("ScreenshotButton")
        updateScreenshotButton()
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.view = screenshotButton
        item.label = "Screenshot"
        item.paletteLabel = "Screenshot"
        return item
    }
}
