// Hosts the MTKView and wires it to the renderer. Fails soft with an on-screen
// message when the GPU lacks Metal 4 — the engine requires it (AGENTS.md
// "Environment & tech stack"); a missing GPU feature must not crash the app.

import AppKit
import MetalKit

final class GameViewController: NSViewController {
    /// Builds the launch scene on the view's Metal device. Set by the
    /// AppDelegate before the window content loads; nil factory or nil
    /// result -> renderer falls back to the synthetic DemoScene. The
    /// factory runs here (not in the AppDelegate) because GPU resources
    /// must be created on the device the view renders with.
    var sceneFactory: ((MTLDevice) -> (scene: RenderScene, camera: SceneCamera)?)?

    private var renderer: Renderer?
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

        guard let device = MTLCreateSystemDefaultDevice(), device.supportsFamily(.metal4) else {
            show(message: "OpenSky requires a GPU with Metal 4 support.")
            return
        }
        mtkView.device = device

        // Synchronous cell scene build at startup — acceptable for 2.7's
        // single small cell; streaming moves this off the launch path later.
        let content = sceneFactory?(device)

        do {
            let newRenderer = try Renderer(
                view: mtkView,
                scene: content?.scene,
                camera: content?.camera,
                input: cameraInput
            )
            newRenderer.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)
            mtkView.delegate = newRenderer
            renderer = newRenderer
        } catch {
            show(message: "Renderer setup failed: \(error)")
        }
    }

    private func show(message: String) {
        let label = NSTextField(labelWithString: message)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}
