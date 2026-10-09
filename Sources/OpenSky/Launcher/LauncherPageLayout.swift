// The one pattern every launcher page follows: a title, grouped settings, a short
// default view, and a "Show details" switch for the technical notes. A status
// shows a symbol and words, never colour alone.

import AppKit

@MainActor
final class LauncherPageLayout {
    static let width: CGFloat = 520
    static let detailsKey = "OpenSkyLauncherShowsDetails"

    let detailsControl = NSSwitch()
    private let pageName: String
    private var detailViews: [NSView] = []
    private let userDefaults: UserDefaults

    /// `pageName` prefixes the ids, such as `Graphics` in `GraphicsShowDetailsControl`.
    init(pageName: String, userDefaults: UserDefaults = .standard) {
        self.pageName = pageName
        self.userDefaults = userDefaults
    }

    var showsDetails: Bool {
        detailsControl.state == .on
    }

    /// Marks `view` as a technical note that only "Show details" reveals.
    @discardableResult
    func detail<View: NSView>(_ view: View) -> View {
        detailViews.append(view)
        view.isHidden = !showsDetails
        return view
    }

    /// A one-line label of the page width. Longer text truncates; the tooltip holds all of it.
    func line(_ identifier: String, mono: Bool = false) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = mono ? PanelMetrics.monoFont : PanelMetrics.captionFont
        label.textColor = Theme.parchmentDim
        label.lineBreakMode = .byTruncatingTail
        label.widthAnchor.constraint(equalToConstant: Self.width).isActive = true
        label.setAccessibilityIdentifier(identifier)
        return label
    }

    /// A fixed note, such as why a feature needs converted files.
    func note(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = PanelMetrics.captionFont
        label.textColor = Theme.parchmentDim
        label.lineBreakMode = .byTruncatingTail
        label.toolTip = text
        return label
    }

    /// A heading over the controls of one group.
    func group(_ title: String, _ views: [NSView]) -> NSStackView {
        let heading = NSTextField(labelWithAttributedString: Theme.headingAttributed(
            title, size: 13, color: Theme.parchment
        ))
        let stack = PanelComponents.group([heading] + views)
        stack.alignment = .leading
        return stack
    }

    /// The page: title, status, groups, and the details switch, in a scroll view.
    func makeView(title: String, status: LauncherStatusView? = nil, groups: [NSView]) -> NSView {
        detailsControl.state = userDefaults.bool(forKey: Self.detailsKey) ? .on : .off
        detailsControl.target = self
        detailsControl.action = #selector(toggleDetails)
        detailsControl.setAccessibilityIdentifier("\(pageName)ShowDetailsControl")
        detailsControl.setAccessibilityLabel("Show details")
        detailsControl.toolTip = "Show the technical notes, such as setting keys and measurements"
        let detailsRow = NSStackView(views: [
            NSTextField(labelWithString: "Show details"),
            detailsControl
        ])
        detailsRow.spacing = PanelMetrics.rowGap
        let heading = NSTextField(labelWithAttributedString: Theme.headingAttributed(
            title, size: 24, color: Theme.gold
        ))
        let header = NSStackView(views: [heading, NSView(), detailsRow])
        header.widthAnchor.constraint(equalToConstant: Self.width).isActive = true
        let stack = NSStackView(views: [header] + (status.map { [$0] } ?? []) + groups)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 24
        stack.edgeInsets = NSEdgeInsets(top: 32, left: 32, bottom: 32, right: 32)
        applyDetails()
        return LauncherScrollView(content: stack)
    }

    @objc private func toggleDetails() {
        userDefaults.set(showsDetails, forKey: Self.detailsKey)
        applyDetails()
    }

    private func applyDetails() {
        for view in detailViews {
            view.isHidden = !showsDetails
        }
    }
}

/// A status: a symbol, a title, and a line under it.
final class LauncherStatusView: NSStackView {
    let symbolView = NSImageView()
    let titleLabel = NSTextField(labelWithString: "")
    let detailLabel = NSTextField(labelWithString: "")

    /// Ids `<name>StatusStatsLabel` and `<name>StatusDetailStatsLabel`.
    init(name: String) {
        super.init(frame: .zero)
        titleLabel.font = .boldSystemFont(ofSize: 15)
        titleLabel.textColor = Theme.parchment
        titleLabel.setAccessibilityIdentifier("\(name)StatusStatsLabel")
        detailLabel.font = PanelMetrics.captionFont
        detailLabel.textColor = Theme.parchmentDim
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.widthAnchor.constraint(equalToConstant: LauncherPageLayout.width - 40)
            .isActive = true
        detailLabel.setAccessibilityIdentifier("\(name)StatusDetailStatsLabel")
        symbolView.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: 22,
            weight: .regular
        )
        let text = PanelComponents.group([titleLabel, detailLabel])
        setViews([symbolView, text], in: .leading)
        spacing = 12
        alignment = .centerY
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func show(symbol: String, title: String, detail: String, colour: NSColor) {
        symbolView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        symbolView.contentTintColor = colour
        titleLabel.stringValue = title
        detailLabel.stringValue = detail
        detailLabel.toolTip = detail
    }
}

/// Scrolls a page that is taller than the window, top first.
final class LauncherScrollView: NSScrollView {
    init(content: NSView) {
        super.init(frame: .zero)
        let document = FlippedView()
        content.translatesAutoresizingMaskIntoConstraints = false
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(content)
        documentView = document
        drawsBackground = false
        hasVerticalScroller = true
        autohidesScrollers = true
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: document.topAnchor),
            content.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            document.widthAnchor.constraint(equalTo: contentView.widthAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    private final class FlippedView: NSView {
        override var isFlipped: Bool {
            true
        }
    }
}
