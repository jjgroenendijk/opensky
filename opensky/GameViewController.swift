// Hosts the MTKView and wires it to the renderer. Fails soft with an on-screen
// message when the GPU lacks Metal 4 — the engine requires it (AGENTS.md
// "Environment & tech stack"); a missing GPU feature must not crash the app.

import AppKit
import MetalKit

final class GameViewController: NSViewController {
    private var renderer: Renderer?

    override func loadView() {
        view = MTKView(frame: NSRect(x: 0, y: 0, width: 1280, height: 720))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let mtkView = view as? MTKView else { return }

        guard let device = MTLCreateSystemDefaultDevice(), device.supportsFamily(.metal4) else {
            show(message: "OpenSky requires a GPU with Metal 4 support.")
            return
        }
        mtkView.device = device

        do {
            let newRenderer = try Renderer(view: mtkView)
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
