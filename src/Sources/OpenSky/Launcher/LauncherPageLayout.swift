// The one pattern every launcher page follows: a title, grouped settings, and a short
// default view. The sidebar's "Show details" switch reveals the technical notes on
// every page at once. A status shows a symbol and words, never colour alone.

import AppKit
import OpenSkyGameData

@MainActor
final class LauncherPageLayout {
    static let width: CGFloat = 540
    static let margin: CGFloat = 40
    /// The narrowest page area that shows `width` and both margins without clipping.
    static let minimumPageWidth = width + 2 * margin

    private var detailViews: [NSView] = []
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = GameDataLocator.settingsDefaults) {
        self.userDefaults = userDefaults
        NotificationCenter.default.addObserver(
            self, selector: #selector(detailsChanged), name: LauncherDetails.changed, object: nil
        )
    }

    var showsDetails: Bool {
        LauncherDetails.isShown(userDefaults)
    }

    /// Marks `view` as a technical note that only "Show details" reveals.
    @discardableResult
    func detail<View: NSView>(_ view: View) -> View {
        detailViews.append(view)
        view.isHidden = !showsDetails
        return view
    }

    /// A one-line readout of the page width. Longer text truncates; set the tooltip.
    func line(_ identifier: String, mono: Bool = false) -> NSTextField {
        let label = text("", mono: mono)
        label.widthAnchor.constraint(equalToConstant: Self.width).isActive = true
        label.setAccessibilityIdentifier(identifier)
        return label
    }

    /// A fixed note, such as why a feature needs converted files.
    func note(_ string: String) -> NSTextField {
        let label = text(string, mono: false)
        label.toolTip = string
        return label
    }

    private func text(_ string: String, mono: Bool) -> NSTextField {
        let label = LauncherText(labelWithString: string)
        label.font = mono ? PanelMetrics.monoFont : LauncherStyle.font(14)
        label.textColor = LauncherStyle.textDim
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    /// A setting row: `title` on the left, `control` on the right.
    func row(_ title: String, _ control: NSView) -> LauncherRow {
        if let popUp = control as? NSPopUpButton {
            LauncherStyle.style(popUp)
        } else if let field = control as? NSTextField, field.isEditable {
            LauncherStyle.style(field)
        }
        return LauncherRow(title: title, control: control)
    }

    /// A checkbox row; the row shows the checkbox's title, so the box draws alone.
    func toggle(_ checkbox: NSButton, indent: CGFloat = 0) -> LauncherRow {
        checkbox.imagePosition = .imageOnly
        return LauncherRow(title: checkbox.title, control: checkbox, indent: indent)
    }

    /// Buttons side by side, their left edge in line with the row titles.
    func buttons(_ buttons: [NSButton]) -> NSStackView {
        let row = NSStackView(views: buttons)
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 6, left: LauncherStyle.textInset, bottom: 6, right: 0)
        return row
    }

    /// A heading and a rule over the controls of one group.
    func group(_ title: String, _ views: [NSView]) -> NSStackView {
        let heading = LauncherText(labelWithAttributedString: LauncherStyle.caps(
            title, size: 15, colour: LauncherStyle.textDim
        ))
        let rule = LauncherStyle.rule(width: Self.width)
        let stack = NSStackView(views: [heading, rule] + views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.setCustomSpacing(6, after: heading)
        return stack
    }

    /// The page: title, status, and groups, in a scroll view.
    func makeView(title: String, status: LauncherStatusView? = nil, groups: [NSView]) -> NSView {
        let stack = NSStackView(
            views: [makeHeader(title: title)] + (status.map { [$0] } ?? []) + groups
        )
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 30
        stack.edgeInsets = NSEdgeInsets(
            top: 28, left: Self.margin, bottom: Self.margin, right: Self.margin
        )
        applyDetails()
        return LauncherScrollView(content: stack)
    }

    private func makeHeader(title: String) -> NSView {
        let heading = NSTextField(labelWithAttributedString: LauncherStyle.caps(
            title, size: 32, colour: LauncherStyle.text
        ))
        let header = NSStackView(views: [heading, LauncherStyle.rule(width: Self.width)])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 10
        return header
    }

    @objc private func detailsChanged() {
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
        titleLabel.font = LauncherStyle.font(18)
        titleLabel.textColor = LauncherStyle.text
        titleLabel.setAccessibilityIdentifier("\(name)StatusStatsLabel")
        detailLabel.font = LauncherStyle.font(14)
        detailLabel.textColor = LauncherStyle.textDim
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
        edgeInsets = NSEdgeInsets(top: 0, left: LauncherStyle.textInset, bottom: 0, right: 0)
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
