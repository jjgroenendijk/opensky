// Content area of the unified shell (issue #98 PR 2). Three layers, back to
// front: the game view (stays in the hierarchy so its renderer + streamer
// survive destination changes), a leading 300pt inspector-panel slot, and a
// full-bleed full-content slot covering the game view for Library
// destinations. While covered, the MTKView is hidden and its draw loop paused
// (owner decision 2026-07-23, reversing the issue #98 low-rate choice): the
// world must not render behind the Asset Browser. Uncovering resumes the loop;
// the streamer re-warms on the next drawn frame.

import AppKit
import MetalKit

final class ShellContentViewController: NSViewController {
    private(set) var gameViewController: GameViewController

    private let panelSlot = NSView()
    private let gameSlot = NSView()
    private let fullContentSlot = NSView()
    private var panelWidth: NSLayoutConstraint?
    private var currentPanelID: String?
    private var fullContentController: NSViewController?

    /// Registered world-inspector panels, keyed + ordered by registry id;
    /// rebuilt when a Settings reload swaps the game controller.
    private var panels: [(id: String, panel: any InspectorPanel)] = []

    init(gameViewController: GameViewController) {
        self.gameViewController = gameViewController
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        panelSlot.translatesAutoresizingMaskIntoConstraints = false
        gameSlot.translatesAutoresizingMaskIntoConstraints = false
        fullContentSlot.translatesAutoresizingMaskIntoConstraints = false
        panelSlot.wantsLayer = true
        panelSlot.layer?.backgroundColor = Theme.panelBackground.cgColor
        let panelEdge = Theme.hairline()
        panelSlot.addSubview(panelEdge)
        NSLayoutConstraint.activate([
            panelEdge.topAnchor.constraint(equalTo: panelSlot.topAnchor),
            panelEdge.bottomAnchor.constraint(equalTo: panelSlot.bottomAnchor),
            panelEdge.trailingAnchor.constraint(equalTo: panelSlot.trailingAnchor),
            panelEdge.widthAnchor.constraint(equalToConstant: 1)
        ])
        view.addSubview(panelSlot)
        view.addSubview(gameSlot)
        view.addSubview(fullContentSlot)
        // Opaque backdrop: full-content destinations fully replace the world
        // view, never float over it.
        fullContentSlot.wantsLayer = true
        fullContentSlot.layer?.backgroundColor = Theme.windowBackground.cgColor
        fullContentSlot.isHidden = true

        let width = panelSlot.widthAnchor.constraint(equalToConstant: 0)
        panelWidth = width
        NSLayoutConstraint.activate([
            panelSlot.topAnchor.constraint(equalTo: view.topAnchor),
            panelSlot.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            panelSlot.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            width,
            gameSlot.topAnchor.constraint(equalTo: view.topAnchor),
            gameSlot.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            gameSlot.leadingAnchor.constraint(equalTo: panelSlot.trailingAnchor),
            gameSlot.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            fullContentSlot.topAnchor.constraint(equalTo: view.topAnchor),
            fullContentSlot.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            fullContentSlot.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            fullContentSlot.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        installGame(gameViewController)
        rebuildPanels()
    }

    // MARK: - Destination display

    /// Bare live render: full-content hidden, panel slot collapsed.
    func showViewport() {
        hideFullContent()
        revealPanel(id: nil)
        refocusGameView()
    }

    /// Inspector panel beside the live render.
    func showInspector(id: String) {
        hideFullContent()
        revealPanel(id: id)
        refocusGameView()
    }

    /// Full-content controller covering the (still-drawing) game view.
    func showFullContent(_ controller: NSViewController) {
        revealPanel(id: nil)
        guard fullContentController !== controller || fullContentSlot.isHidden else { return }
        removeFullContentController()
        fullContentController = controller
        addChild(controller)
        let content = controller.view
        content.translatesAutoresizingMaskIntoConstraints = false
        fullContentSlot.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: fullContentSlot.topAnchor),
            content.bottomAnchor.constraint(equalTo: fullContentSlot.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: fullContentSlot.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: fullContentSlot.trailingAnchor)
        ])
        fullContentSlot.isHidden = false
        setGameCovered(true)
    }

    /// Puts key focus back on the game view so WASD/mouse capture work after
    /// sidebar or toolbar interaction.
    func refocusGameView() {
        guard let window = view.window else { return }
        window.makeFirstResponder(gameViewController.view)
    }

    // MARK: - Settings reload

    /// Swaps in a freshly built game controller (new renderer + streamer over
    /// a new data root) and rebuilds every inspector panel against it. The
    /// shell re-applies the current destination afterwards.
    func replaceGame(with newController: GameViewController) {
        for entry in panels {
            entry.panel.stopInspecting()
            entry.panel.view.removeFromSuperview()
            entry.panel.removeFromParent()
        }
        panels = []
        currentPanelID = nil
        gameViewController.view.removeFromSuperview()
        gameViewController.removeFromParent()
        gameViewController = newController
        guard isViewLoaded else { return }
        installGame(newController)
        rebuildPanels()
    }

    // MARK: - Panel + game plumbing

    private func installGame(_ controller: GameViewController) {
        addChild(controller)
        let gameView = controller.view
        gameView.translatesAutoresizingMaskIntoConstraints = false
        gameSlot.addSubview(gameView)
        NSLayoutConstraint.activate([
            gameView.topAnchor.constraint(equalTo: gameSlot.topAnchor),
            gameView.bottomAnchor.constraint(equalTo: gameSlot.bottomAnchor),
            gameView.leadingAnchor.constraint(equalTo: gameSlot.leadingAnchor),
            gameView.trailingAnchor.constraint(equalTo: gameSlot.trailingAnchor)
        ])
        setGameCovered(!fullContentSlot.isHidden)
    }

    /// Builds every world-inspector panel from the registry, wired to the
    /// current game controller, stacked hidden in the panel slot.
    private func rebuildPanels() {
        let context = WorldPanelContext(providers: gameViewController)
        panels = DestinationRegistry.worldInspectors.compactMap { descriptor in
            guard case let .worldInspector(makePanel) = descriptor.content else { return nil }
            return (descriptor.id, makePanel(context))
        }
        for entry in panels {
            addChild(entry.panel)
            let panelView = entry.panel.view
            panelView.translatesAutoresizingMaskIntoConstraints = false
            panelSlot.addSubview(panelView)
            NSLayoutConstraint.activate([
                panelView.topAnchor.constraint(equalTo: panelSlot.topAnchor),
                panelView.bottomAnchor.constraint(equalTo: panelSlot.bottomAnchor),
                panelView.leadingAnchor.constraint(equalTo: panelSlot.leadingAnchor),
                panelView.trailingAnchor.constraint(equalTo: panelSlot.trailingAnchor)
            ])
            panelView.isHidden = true
        }
    }

    /// Reveals the panel for `id` (hiding the rest) or collapses the slot.
    /// Only the revealed panel inspects; the others stop ticking.
    private func revealPanel(id: String?) {
        currentPanelID = id
        let active = panel(for: id)
        for entry in panels {
            let isActive = entry.id == id
            entry.panel.view.isHidden = !isActive
            if !isActive {
                entry.panel.stopInspecting()
            }
        }
        panelWidth?.constant = active != nil ? PanelMetrics.panelWidth : 0
        if active != nil, view.window != nil {
            active?.startInspecting()
        } else {
            active?.stopInspecting()
        }
    }

    private func panel(for id: String?) -> (any InspectorPanel)? {
        guard let id else { return nil }
        return panels.first { $0.id == id }?.panel
    }

    private func hideFullContent() {
        guard !fullContentSlot.isHidden else { return }
        fullContentSlot.isHidden = true
        removeFullContentController()
        setGameCovered(false)
    }

    private func removeFullContentController() {
        fullContentController?.view.removeFromSuperview()
        fullContentController?.removeFromParent()
        fullContentController = nil
    }

    private func setGameCovered(_ covered: Bool) {
        guard let mtkView = gameViewController.view as? MTKView else { return }
        mtkView.isPaused = covered
        mtkView.isHidden = covered
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        panel(for: currentPanelID)?.startInspecting()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        for entry in panels {
            entry.panel.stopInspecting()
        }
    }
}
