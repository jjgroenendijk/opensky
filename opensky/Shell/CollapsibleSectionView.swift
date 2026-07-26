// A disclosure header above a section's content (issue #98). Collapsing hides
// the content so long, knob-heavy panels stay scannable as OpenSky's config
// surface grows. Collapse state persists per section id across launches.
//
// This is an NSStackView, not a plain NSView, and that is load-bearing: Auto
// Layout only reclaims a hidden view's space when it is an *arranged* subview
// of a stack. Pinned as an ordinary subview, a collapsed section kept its full
// expanded height and the panel column reserved a blank block for it
// (docs/tools/app-ui.md, "collapsed section occupies its header height").

import AppKit

final class CollapsibleSectionView: NSStackView {
    private let disclosure = NSButton()
    private let overrideIndicator = NSTextField(labelWithString: "●")
    private let resetButton = NSButton(title: "Reset", target: nil, action: nil)
    private let content: NSView
    private let sectionID: String
    private let onReset: (() -> Void)?

    /// Wraps `content` under a disclosure header titled `title`. `identifier`
    /// keys both the accessibility id (`PanelSection-<id>`) and the persisted
    /// expanded/collapsed state.
    init(
        title: String,
        identifier: String,
        content: NSView,
        isOverridden: Bool = false,
        onReset: (() -> Void)? = nil
    ) {
        self.content = content
        sectionID = identifier
        self.onReset = onReset
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        disclosure.setButtonType(.pushOnPushOff)
        disclosure.bezelStyle = .disclosure
        disclosure.title = ""
        disclosure.target = self
        disclosure.action = #selector(toggle)
        disclosure.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.attributedStringValue = Theme.headingAttributed(
            title,
            size: 12,
            color: Theme.gold
        )
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let spacer = NSView()
        overrideIndicator.textColor = Theme.gold
        overrideIndicator.toolTip = "This section differs from its defaults"
        overrideIndicator.setAccessibilityIdentifier(
            "PanelSection-\(sectionID)-OverrideIndicator"
        )
        resetButton.bezelStyle = .inline
        resetButton.target = self
        resetButton.action = #selector(reset)
        resetButton.setAccessibilityIdentifier("PanelSection-\(sectionID)-ResetControl")

        let header = NSStackView(
            views: [disclosure, titleLabel, spacer, overrideIndicator, resetButton]
        )
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 4
        header.translatesAutoresizingMaskIntoConstraints = false
        header.setAccessibilityIdentifier("PanelSection-\(sectionID)")

        content.translatesAutoresizingMaskIntoConstraints = false
        orientation = .vertical
        alignment = .leading
        spacing = 4
        addArrangedSubview(header)
        addArrangedSubview(content)
        // The stack's .leading alignment supplies the leading edge; pin the
        // trailing edges so header and content span the section's full width.
        NSLayoutConstraint.activate([
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        applyExpanded(Self.loadExpanded(sectionID))
        setOverridden(isOverridden)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    /// Whether the content is currently revealed.
    var isExpanded: Bool {
        disclosure.state == .on
    }

    /// Sets and persists the expanded state (also driven by the disclosure).
    func setExpanded(_ expanded: Bool) {
        applyExpanded(expanded)
        Self.storeExpanded(sectionID, expanded: expanded)
    }

    /// Shows the shared gold marker and Reset button only for a non-default state.
    func setOverridden(_ overridden: Bool) {
        overrideIndicator.isHidden = !overridden
        resetButton.isHidden = !overridden
    }

    @objc private func toggle() {
        setExpanded(disclosure.state == .on)
    }

    @objc private func reset() {
        onReset?()
    }

    private func applyExpanded(_ expanded: Bool) {
        disclosure.state = expanded ? .on : .off
        content.isHidden = !expanded
        // Belt and braces: hiding an arranged subview already collapses it, but
        // stating the visibility priority makes the intent explicit and survives
        // a caller that unhides `content` behind our back.
        setVisibilityPriority(expanded ? .mustHold : .notVisible, for: content)
    }

    // MARK: Persistence

    private static func key(_ sectionID: String) -> String {
        "panelSection.expanded.\(sectionID)"
    }

    private static func loadExpanded(_ sectionID: String) -> Bool {
        let defaults = UserDefaults.standard
        // Default to expanded when unset so panels open fully revealed.
        guard defaults.object(forKey: key(sectionID)) != nil else { return true }
        return defaults.bool(forKey: key(sectionID))
    }

    private static func storeExpanded(_ sectionID: String, expanded: Bool) {
        UserDefaults.standard.set(expanded, forKey: key(sectionID))
    }
}
