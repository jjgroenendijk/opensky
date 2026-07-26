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
    /// View > Hide Inspector state. Applies to whichever world destination is
    /// frontmost, which is what the retired `Viewport` row used to do.
    private var isInspectorHidden = false

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
        sidebar.isDestinationOverridden = { [weak self] id in
            self?.content.isDestinationOverridden(id: id) ?? false
        }
        content.onOverrideStateChange = { [weak self] in
            self?.sidebar.refreshOverrideIndicators()
        }
        // Default selection on launch: the plain live render.
        sidebar.select(id: DestinationRegistry.defaultDestinationID)
        sidebar.refreshOverrideIndicators()
    }

    // MARK: - Destination routing

    private func show(_ descriptor: DestinationDescriptor) {
        currentDestinationID = descriptor.id
        switch descriptor.content {
        case .viewport:
            content.showViewport()
        case .worldInspector:
            if isInspectorHidden {
                content.showViewport()
            } else {
                content.showInspector(id: descriptor.id)
            }
        case let .fullContent(makeController):
            let controller = fullContentControllers[descriptor.id]
                ?? makeController(fullContentContext)
            fullContentControllers[descriptor.id] = controller
            content.showFullContent(controller)
        }
        updateScreenshotButton()
        sidebar.refreshOverrideIndicators()
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
        sidebar.refreshOverrideIndicators()
    }

    // MARK: - View-menu commands

    /// True when the frontmost destination actually has an inspector column to
    /// hide; a full-content destination (Asset Browser) has none.
    var canToggleInspector: Bool {
        currentDestinationID
            .flatMap(DestinationRegistry.destination(id:))?.isWorldInspector ?? false
    }

    /// True while the inspector column is collapsed by the View-menu command.
    var isInspectorCollapsed: Bool {
        isInspectorHidden
    }

    /// Whether the always-on frame overlay is wanted (persisted).
    var isFrameHUDEnabled: Bool {
        content.isFrameHUDEnabled
    }

    /// View > Show Frame HUD. Reaches the shell through the responder chain.
    @objc func toggleFrameHUD(_: Any?) {
        content.isFrameHUDEnabled.toggle()
    }

    /// View > Hide Inspector. Collapses or restores the panel column of the
    /// frontmost world destination.
    @objc func toggleInspectorColumn(_: Any?) {
        guard
            let id = currentDestinationID,
            let descriptor = DestinationRegistry.destination(id: id),
            descriptor.isWorldInspector
        else { return }
        isInspectorHidden.toggle()
        show(descriptor)
    }

    /// View > Reset all overrides. Registry actions reach unopened panels
    /// without constructing them, then cached panels resync their controls.
    @objc func resetAllOverrides(_: Any?) {
        content.resetAllOverrides()
        sidebar.refreshOverrideIndicators()
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
        static let sidebarToggle = NSToolbarItem.Identifier("SidebarToggle")
        static let screenshot = NSToolbarItem.Identifier("Screenshot")
    }

    @objc private func toggleSidebarItem() {
        toggleSidebar(nil)
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

/// Menu validation for the two shell commands: a command that cannot apply is
/// greyed out rather than silently doing nothing, and each carries a checkmark
/// showing which way it will go. Everything else falls through to
/// `NSSplitViewController`'s own validation, which is what keeps the sidebar
/// item's title in sync.
extension AppShellViewController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleFrameHUD):
            menuItem.state = isFrameHUDEnabled ? .on : .off
            return true
        case #selector(toggleInspectorColumn):
            menuItem.state = isInspectorHidden ? .on : .off
            return canToggleInspector
        case #selector(resetAllOverrides):
            return content.hasOverrides
        default:
            return validateUserInterfaceItem(menuItem)
        }
    }
}

extension AppShellViewController: NSToolbarDelegate {
    /// No `.sidebarTrackingSeparator`: it pins items to the split divider, so
    /// the sidebar toggle sat inside the sidebar region and slid left whenever
    /// the sidebar collapsed. Laying the toolbar out left-to-right from a fixed
    /// origin keeps the toggle put in both states (docs/tools/app-ui.md).
    func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        [ToolbarItemID.sidebarToggle, .flexibleSpace, ToolbarItemID.screenshot]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar _: Bool
    ) -> NSToolbarItem? {
        if itemIdentifier == ToolbarItemID.sidebarToggle {
            return makeSidebarToggleItem(identifier: itemIdentifier)
        }
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

    /// A custom item rather than the system `.toggleSidebar`, so the toggle
    /// carries an accessibility id like every other control.
    private func makeSidebarToggleItem(
        identifier: NSToolbarItem.Identifier
    ) -> NSToolbarItem {
        let button = NSButton(
            image: NSImage(
                systemSymbolName: "sidebar.leading",
                accessibilityDescription: "Toggle sidebar"
            ) ?? NSImage(),
            target: self,
            action: #selector(toggleSidebarItem)
        )
        button.bezelStyle = .toolbar
        button.toolTip = "Show or hide the sidebar"
        button.setAccessibilityIdentifier("SidebarToggleButton")
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.view = button
        item.label = "Sidebar"
        item.paletteLabel = "Sidebar"
        return item
    }
}
