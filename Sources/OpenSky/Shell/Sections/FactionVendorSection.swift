// World > Crime & Factions > Vendor: the vendor role from the subject's
// memberships, and an override to trade under another vendor faction. The
// override is a setting, so "Reset all" clears it.

import AppKit
import OpenSkyCrime

final class FactionVendorSection: CrimeFactionPanelSection {
    static let resolvedTitle = "Resolved from memberships"

    let overrideControl = NSPopUpButton()
    let barterControl = NSButton(title: "Barter", target: nil, action: nil)

    private let statsLabel = PanelComponents.statsLabel(identifier: "FactionVendorStatsLabel")
    private var options: [FactionOption] = []

    override var sectionTitle: String {
        "Vendor"
    }

    override var sectionIdentifier: String {
        "factionVendor"
    }

    override var isOverridden: Bool {
        provider?.vendorOverrideSelection != nil
    }

    var readout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configurePopUp(
            overrideControl, target: self, action: #selector(overrideChanged),
            identifier: "FactionVendorOverrideControl", width: PanelMetrics.contentWidth
        )
        PanelComponents.configureButton(
            barterControl, target: self, action: #selector(barter),
            identifier: "FactionBarterControl"
        )
        return [
            PanelComponents.note(
                "The subject's vendor faction: the merchant chest it sells from, the "
                    + "hours it trades, its buy/sell keyword list and whether it fences "
                    + "stolen goods. Pick a vendor faction to trade under its rules "
                    + "instead; Barter opens the barter menu with the subject under "
                    + "whichever applies, as Actor.ShowBarterMenu does."
            ),
            PanelComponents.group([overrideControl, barterControl]),
            statsLabel
        ]
    }

    override func syncControls() {
        barterControl.isEnabled = currentSnapshot?.isAvailable == true
        syncVendors()
    }

    override func refreshReadout() {
        guard let snapshot = currentSnapshot else {
            statsLabel.stringValue = "Vendor: unavailable"
            return
        }
        syncVendors(snapshot)
        statsLabel.stringValue = CrimeFactionReadout.vendorText(for: snapshot)
    }

    override func resetToDefaults() {
        provider?.vendorOverrideSelection = nil
    }

    private func syncVendors(_ snapshot: CrimeFactionControlSnapshot? = nil) {
        let snapshot = snapshot ?? currentSnapshot
        options = sync(
            overrideControl,
            options: snapshot?.vendorFactions ?? [],
            shown: options,
            leading: [Self.resolvedTitle],
            selected: snapshot?.vendorOverride
        )
    }

    @objc private func overrideChanged() {
        provider?.vendorOverrideSelection =
            selectedOption(of: overrideControl, in: options, leading: 1)?.key
        finishInteraction()
    }

    @objc private func barter() {
        provider?.barterWithSocialSubject()
        finishInteraction()
    }
}
