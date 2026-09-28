// World > Crime & Factions > Vendor (issue #507): the vendor role the subject's
// memberships resolve (issue #506) — chest, hours, buy/sell list, fence — and
// the dev override that trades under another vendor faction instead.
//
// The override is the one control on this destination that is a setting rather
// than world state: it changes which rules the next barter uses without
// changing what anybody is a member of. So it is the one "Reset all" clears,
// and the section reports it as an override.

import AppKit
import OpenSkyEngine

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
