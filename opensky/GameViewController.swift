// Hosts the MTKView and wires it to the renderer. Fails soft with an on-screen
// message when the GPU lacks Metal 4 — the engine requires it (AGENTS.md
// "Environment & tech stack"); a missing GPU feature must not crash the app.

import AppKit
import MetalKit
import OSLog

final class GameViewController: NSViewController {
    enum ScreenshotError: LocalizedError {
        case rendererNotReady

        var errorDescription: String? {
            "World renderer is not ready for a screenshot."
        }
    }

    /// Locator failure shown inside World. Settings remains reachable so the
    /// root can be corrected without relaunching or dismissing an alert loop.
    var startupErrorMessage: String?

    /// Builds the off-main cell provider on the view's Metal device. Set by
    /// the AppDelegate before the window content loads; nil factory or nil
    /// result (missing game data / setup throw) -> no streamer, renderer
    /// falls back to the synthetic DemoScene. The factory runs here (not in
    /// the AppDelegate) because the asset libraries bind GPU resources to the
    /// device the view renders with.
    var cellProviderFactory: ((MTLDevice) -> (any CellSceneProvider)?)?

    private var renderer: Renderer?
    var canWriteScreenshot: Bool {
        renderer != nil
    }

    /// Retains the streaming controller (and, through it, the build runner +
    /// provider) for the window's lifetime.
    private var streamer: CellStreamer?
    /// Free-fly input shared with the renderer; the view writes it from
    /// NSEvents, the renderer drains it each frame (todo 2.8).
    private let cameraInput = CameraInputState()

    override func loadView() {
        let gameView = GameMetalView(frame: NSRect(x: 0, y: 0, width: 1280, height: 720))
        gameView.input = cameraInput
        view = gameView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let mtkView = view as? MTKView else { return }

        if let startupErrorMessage {
            show(message: startupErrorMessage)
            return
        }

        guard let device = MTLCreateSystemDefaultDevice(), device.supportsFamily(.metal4) else {
            show(message: "OpenSky requires a GPU with Metal 4 support.")
            return
        }
        mtkView.device = device

        // Async launch: no scene is built here. A provider (game data) starts
        // the renderer on an empty scene and streams cells in around the
        // camera; no provider (missing data / setup throw) falls back to the
        // synthetic DemoScene so the window is never blank forever.
        let provider = cellProviderFactory?(device)

        do {
            let newRenderer = try Renderer(
                view: mtkView,
                scene: provider != nil ? RenderScene(instances: []) : nil,
                camera: nil,
                input: cameraInput
            )
            newRenderer.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)
            mtkView.delegate = newRenderer
            renderer = newRenderer
            if let provider {
                startStreaming(provider: provider, renderer: newRenderer)
            }
        } catch {
            show(message: "Renderer setup failed: \(error)")
        }
    }

    /// Wires a streamer over the provider: builds run off-main on a serial
    /// runner, the recomposed scene swaps in via `Renderer.setScene`, and the
    /// renderer's per-frame hook drives the streamer with the live camera
    /// position. Weak captures both ways -> no retain cycle (this controller
    /// owns both renderer + streamer).
    private func startStreaming(provider: any CellSceneProvider, renderer: Renderer) {
        let runner = SerialCellBuildRunner(provider: provider)
        let controller = CellStreamer(
            center: CellCoordinate(x: FirstRenderCell.gridX, y: FirstRenderCell.gridY),
            runner: runner,
            sink: { [weak renderer] scene, camera in
                do {
                    try renderer?.setScene(scene, camera: camera)
                } catch {
                    Self.logger.error(
                        "[ERROR] scene swap failed: \(String(describing: error), privacy: .public)"
                    )
                }
            }
        )
        renderer.onFrame = { [weak controller] position in
            controller?.update(cameraPosition: position)
        }
        streamer = controller
    }

    /// Saves the live World camera + current streamed scene, excluding app
    /// chrome. Runs on main, same as draw(in:), so renderer state cannot race.
    func writeScreenshot(to url: URL) throws {
        guard let renderer, let view = view as? MTKView else {
            throw ScreenshotError.rendererNotReady
        }
        let width = Int(view.drawableSize.width.rounded())
        let height = Int(view.drawableSize.height.rounded())
        guard width > 0, height > 0 else {
            throw ScreenshotError.rendererNotReady
        }
        let texture = try renderer.renderOffscreen(width: width, height: height)
        try FrameScreenshot.write(texture: texture, to: url)
    }

    private static let logger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "CellStream"
    )

    private func show(message: String) {
        let label = NSTextField(wrappingLabelWithString: message)
        label.alignment = .center
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32)
        ])
    }
}
