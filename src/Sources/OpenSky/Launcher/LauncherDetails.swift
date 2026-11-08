// One "Show details" choice for the whole launcher. The switch sits at the foot of the
// sidebar; every page and the Cmd+, window show or hide their technical notes with it.

import AppKit
import OpenSkyGameData

@MainActor
enum LauncherDetails {
    static let key = "OpenSkyLauncherShowsDetails"
    static let changed = Notification.Name("OpenSkyLauncherDetailsChanged")

    static func isShown(_ defaults: UserDefaults = GameDataLocator.settingsDefaults) -> Bool {
        defaults.bool(forKey: key)
    }

    static func set(_ shown: Bool, defaults: UserDefaults = GameDataLocator.settingsDefaults) {
        defaults.set(shown, forKey: key)
        NotificationCenter.default.post(name: changed, object: nil)
    }
}

/// The sidebar's foot: the "Show details" label and its switch.
final class LauncherDetailsSwitchView: NSStackView {
    let control = NSSwitch()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = GameDataLocator.settingsDefaults) {
        self.defaults = defaults
        super.init(frame: .zero)
        control.state = LauncherDetails.isShown(defaults) ? .on : .off
        control.controlSize = .small
        control.target = self
        control.action = #selector(toggle)
        control.setAccessibilityIdentifier("LauncherShowDetailsControl")
        control.setAccessibilityLabel("Show details")
        control.toolTip = "Show the technical notes and developer settings on every page"
        let label = NSTextField(labelWithAttributedString: LauncherStyle.caps(
            "Show details", size: 13, colour: LauncherStyle.textDim
        ))
        setViews([label, NSView(), control], in: .leading)
        spacing = 8
        alignment = .centerY
        edgeInsets = NSEdgeInsets(top: 12, left: 22, bottom: 16, right: 16)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    @objc private func toggle() {
        LauncherDetails.set(control.state == .on, defaults: defaults)
    }
}
