// Settings window (Cmd+,): configure the game data root. Validation +
// persistence live in GameDataLocator (AppKit-free, unit-tested); this file
// only wires the panel UI. Choosing a folder persists it to the shared
// defaults domain so the CLI picks it up too.

import AppKit

final class SettingsWindowController: NSWindowController {
    /// Called after the persisted data root changes (chosen or reset).
    var onDataRootChanged: (() -> Void)?

    private let pathLabel = NSTextField(wrappingLabelWithString: "")
    private let noteLabel = NSTextField(wrappingLabelWithString: "")

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 160),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        self.init(window: window)
        window.contentView = makeContentView()
        window.center()
        refresh()
    }

    // MARK: - Layout

    private func makeContentView() -> NSView {
        let heading = NSTextField(labelWithString: "Game Data Root")
        heading.font = .boldSystemFont(ofSize: NSFont.systemFontSize)

        pathLabel.isSelectable = true
        pathLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)

        noteLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        noteLabel.textColor = .secondaryLabelColor

        let chooseButton = NSButton(
            title: "Choose…",
            target: self,
            action: #selector(chooseDataRoot)
        )
        let resetButton = NSButton(
            title: "Use Default",
            target: self,
            action: #selector(useDefaultRoot)
        )
        let buttons = NSStackView(views: [resetButton, chooseButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY

        let stack = NSStackView(views: [heading, pathLabel, noteLabel, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.setCustomSpacing(12, after: noteLabel)
        pathLabel.widthAnchor.constraint(
            equalTo: stack.widthAnchor,
            constant: -32
        ).isActive = true
        noteLabel.widthAnchor.constraint(
            equalTo: stack.widthAnchor,
            constant: -32
        ).isActive = true
        return stack
    }

    // MARK: - State

    /// Re-resolves the root and updates the labels. `problem` (a failed
    /// choice) shows in place of the source note.
    private func refresh(problem: String? = nil) {
        do {
            let root = try GameDataLocator.locate()
            pathLabel.stringValue = root.installURL.path(percentEncoded: false)
            noteLabel.stringValue = problem ?? Self.sourceNote(for: root.source)
        } catch {
            pathLabel.stringValue = "Not located"
            noteLabel.stringValue = problem ?? error.localizedDescription
        }
        noteLabel.textColor = problem == nil ? .secondaryLabelColor : .systemRed
    }

    private static func sourceNote(for source: GameDataRoot.Source) -> String {
        switch source {
        case .environment:
            "Set by the \(GameDataLocator.environmentKey) environment variable — "
                + "it overrides the choice made here."
        case .userDefaults:
            "Chosen in Settings."
        case .steamDefault:
            "Default Steam install location."
        }
    }

    // MARK: - Actions

    @objc private func chooseDataRoot() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message =
            "Select the Skyrim Special Edition install folder (contains Data/Skyrim.esm)."
        panel.prompt = "Use Folder"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            let path = url.path(percentEncoded: false)
            do {
                try GameDataLocator.saveUserChoice(path: path)
                refresh()
                onDataRootChanged?()
            } catch {
                refresh(
                    problem: "Not a Skyrim SE install: \(path) — "
                        + "expected a folder containing Data/Skyrim.esm."
                )
            }
        }
    }

    @objc private func useDefaultRoot() {
        GameDataLocator.clearUserChoice()
        refresh()
        onDataRootChanged?()
    }
}
