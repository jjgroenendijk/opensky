// World > Container Menu > Merchant: nominates the container reference that
// stands in as a merchant (M12.2.3, issue #179).
//
// This is the seam the milestone's scope calls for. There is no merchant system
// — vanilla merchants sell out of a faction-linked chest, and no VENDR-style
// faction data is decoded — so a developer points the menu at a container and
// that container's stock and gold are the merchant's. Every resident container
// is offered by name, plus the one under the crosshair, so a nomination never
// needs a FormID typed in.

import AppKit

final class ContainerMerchantSection: PanelSectionViewController {
    weak var provider: (any ContainerMenuControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let merchantControl = NSPopUpButton()
    let crosshairControl = NSButton(title: "Use crosshair target", target: nil, action: nil)
    private let statsLabel = PanelComponents.statsLabel(identifier: "ContainerMerchantStatsLabel")

    /// The options behind the popup's rows, so a selection maps back to a
    /// reference without parsing the title the user sees.
    private var options: [ContainerMenuMerchantOption] = []

    var statsReadout: String {
        statsLabel.stringValue
    }

    override var sectionTitle: String {
        "Merchant"
    }

    override var sectionIdentifier: String {
        "containerMerchant"
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configurePopUp(
            merchantControl,
            target: self,
            action: #selector(merchantChanged),
            identifier: "ContainerMerchantSelectControl",
            width: PanelMetrics.contentWidth
        )
        PanelComponents.configureButton(
            crosshairControl,
            target: self,
            action: #selector(crosshairTapped),
            identifier: "ContainerMerchantCrosshairControl"
        )
        return [
            PanelComponents.group([merchantControl, crosshairControl]),
            statsLabel
        ]
    }

    override func syncControls() {
        reloadOptions()
        crosshairControl.isEnabled = provider != nil
    }

    override func refreshReadout() {
        guard let snapshot = provider?.containerMenuSnapshot else {
            statsLabel.stringValue = "Merchant: unavailable"
            return
        }
        reloadOptions(snapshot: snapshot)
        statsLabel.stringValue = Self.readout(for: snapshot)
    }

    /// Rebuilds the popup only when the resident container list actually
    /// changed. The readout ticks at 2 Hz, and rebuilding a popup under an open
    /// menu would close it in the user's hand.
    private func reloadOptions(snapshot: ContainerMenuControlSnapshot? = nil) {
        guard let snapshot = snapshot ?? provider?.containerMenuSnapshot else {
            options = []
            merchantControl.removeAllItems()
            merchantControl.isEnabled = false
            return
        }
        merchantControl.isEnabled = !snapshot.merchantOptions.isEmpty
        guard snapshot.merchantOptions != options else {
            selectCurrentMerchant(snapshot)
            return
        }
        options = snapshot.merchantOptions
        merchantControl.removeAllItems()
        merchantControl.addItems(withTitles: options.map(Self.title(for:)))
        selectCurrentMerchant(snapshot)
    }

    private func selectCurrentMerchant(_ snapshot: ContainerMenuControlSnapshot) {
        guard
            let reference = snapshot.selectedMerchant,
            let index = options.firstIndex(where: { $0.reference == reference })
        else { return }
        merchantControl.selectItem(at: index)
    }

    /// A popup row names the container, what it holds and what it can pay with,
    /// because "which chest" is not a useful question when four say "Chest".
    nonisolated static func title(for option: ContainerMenuMerchantOption) -> String {
        "\(option.name) · \(option.itemCount) items · \(option.gold) gold "
            + "· \(option.reference)"
    }

    nonisolated static func readout(for snapshot: ContainerMenuControlSnapshot) -> String {
        guard !snapshot.merchantOptions.isEmpty else {
            return "Merchant: no resident containers.\n"
                + "Load a cell holding one, or look at a chest and use the button."
        }
        let selected = snapshot.selectedMerchant
            .flatMap { reference in
                snapshot.merchantOptions.first { $0.reference == reference }
            }
            .map(title(for:)) ?? "none"
        return """
        Merchant: \(selected)
        Resident containers: \(snapshot.merchantOptions.count)
        Pricing: factor \(String(format: "%.4f", snapshot.priceFactor)) · \
        \(snapshot.pricingSource)
        """
    }

    @objc private func merchantChanged() {
        let index = merchantControl.indexOfSelectedItem
        guard options.indices.contains(index) else { return }
        provider?.selectContainerMenuMerchant(options[index].reference)
        finishInteraction()
    }

    @objc private func crosshairTapped() {
        provider?.selectContainerMenuMerchantFromInteraction()
        finishInteraction()
    }
}
