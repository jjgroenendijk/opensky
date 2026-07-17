// Browser shell (scaffold): shows the located data root or the locator's
// error message. Browse + preview UI lands with the rest of todo 2.10.

import AppKit

final class PreviewViewController: NSViewController {
    /// Located install, set by the app delegate before the view loads;
    /// nil -> `startupErrorMessage` explains why.
    var gameDataRoot: GameDataRoot?
    /// Locator failure text shown in-window (the app still launches).
    var startupErrorMessage: String?

    private let statusLabel = NSTextField(labelWithString: "")

    override func loadView() {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800))
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 0
        content.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            statusLabel.widthAnchor.constraint(
                lessThanOrEqualTo: content.widthAnchor,
                constant: -80
            )
        ])
        view = content
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if let root = gameDataRoot {
            statusLabel.stringValue = "Game data: \(root.dataURL.path(percentEncoded: false))"
        } else {
            statusLabel.stringValue = startupErrorMessage ?? "Game data not located."
        }
    }
}
