// World > AI & Navigation > Idles: the idle markers of the loaded cells, one
// marker's idles and their tree, and the selector trace of the selected actor.

import AppKit
import OpenSkyFormatsESM
import OpenSkyWorld

final class AIIdleSection: PanelSectionViewController {
    weak var provider: (any IdleControlProviding)? {
        didSet { reloadIfLoaded() }
    }

    weak var selectionProvider: (any AINavigationControlProviding)? {
        didSet { reloadIfLoaded() }
    }

    let markersControl = NSButton(
        checkboxWithTitle: "Send sandboxing actors to markers", target: nil, action: nil
    )
    let markerControl = NSPopUpButton()
    let idleControl = NSPopUpButton()
    let ignoreConditionsControl = NSButton(
        checkboxWithTitle: "Ignore conditions", target: nil, action: nil
    )
    let fireControl = NSButton(title: "Play idle", target: nil, action: nil)
    let pickControl = NSButton(title: "Pick at marker", target: nil, action: nil)

    private let markersLabel = PanelComponents.statsLabel(identifier: "IdleMarkersLabel")
    private let statsLabel = PanelComponents.statsLabel(identifier: "IdleStatsLabel")
    private var markers: [IdleMarkerReadout] = []

    override var sectionTitle: String {
        "Idles"
    }

    override var sectionIdentifier: String {
        "aiIdles"
    }

    override var isOverridden: Bool {
        Self.isOverridden(provider: provider)
    }

    /// Markers off is the one setting here; the default sends actors to them.
    static func isOverridden(provider: (any IdleControlProviding)?) -> Bool {
        guard let snapshot = provider?.idleSnapshot(for: nil) else { return false }
        return snapshot.isAvailable && !snapshot.usesIdleMarkers
    }

    static func resetToDefaults(provider: (any IdleControlProviding)?) {
        provider?.setUsesIdleMarkers(true)
    }

    override func makeContentViews() -> [NSView] {
        markersControl.toolTip =
            "Actors on a sandbox package walk to a free idle marker and idle there."
        markerControl.toolTip = "Idle markers in the loaded cells."
        idleControl.toolTip = "The idles the marker offers."
        ignoreConditionsControl.toolTip = "Plays the idle even when its conditions fail."
        fireControl.toolTip = "Plays the chosen idle on the selected actor."
        pickControl.toolTip = "Runs the marker's own choice for the selected actor."
        PanelComponents.configureCheckbox(
            markersControl, target: self, action: #selector(markersToggled),
            identifier: "IdleMarkersControl"
        )
        PanelComponents.configurePopUp(
            markerControl, target: self, action: #selector(markerChanged),
            identifier: "IdleMarkerControl", width: PanelMetrics.contentWidth
        )
        PanelComponents.configurePopUp(
            idleControl, target: self, action: #selector(idleChanged),
            identifier: "IdleEntryControl", width: PanelMetrics.contentWidth
        )
        PanelComponents.configureCheckbox(
            ignoreConditionsControl, target: self, action: #selector(idleChanged),
            identifier: "IdleIgnoreConditionsControl"
        )
        PanelComponents.configureButton(
            fireControl, target: self, action: #selector(fire), identifier: "IdleFireControl"
        )
        PanelComponents.configureButton(
            pickControl, target: self, action: #selector(pick), identifier: "IdlePickControl"
        )
        return [
            PanelComponents.group([markersControl, markersLabel]),
            PanelComponents.group([markerControl, idleControl, ignoreConditionsControl]),
            PanelComponents.buttonRow([fireControl, pickControl]),
            statsLabel
        ]
    }

    override func syncControls() {
        let snapshot = provider?.idleSnapshot(for: selectionProvider?.selectedAIActor)
        markersControl.state = snapshot?.usesIdleMarkers == true ? .on : .off
        markersControl.isEnabled = snapshot?.isAvailable == true
        reloadMarkers(snapshot?.markers ?? [])
        let hasActor = selectionProvider?.selectedAIActor != nil
        fireControl.isEnabled = hasActor && selectedIdle != nil
        pickControl.isEnabled = hasActor && selectedMarker != nil
    }

    override func refreshReadout() {
        guard let provider else {
            markersLabel.stringValue = "Idle markers: unavailable"
            statsLabel.stringValue = ""
            return
        }
        let snapshot = provider.idleSnapshot(for: selectionProvider?.selectedAIActor)
        reloadMarkers(snapshot.markers)
        markersLabel.stringValue = IdleReadout.markersText(for: snapshot)
        let tree = selectedIdle.map(provider.idleTree(below:)) ?? []
        statsLabel.stringValue = [
            IdleReadout.markerText(selectedMarker),
            IdleReadout.treeText(tree),
            IdleReadout.reportText(snapshot.report)
        ].joined(separator: "\n")
    }

    override func resetToDefaults() {
        Self.resetToDefaults(provider: provider)
        syncControls()
    }

    private var selectedMarker: IdleMarkerReadout? {
        let index = markerControl.indexOfSelectedItem
        return markers.indices.contains(index) ? markers[index] : nil
    }

    private var selectedIdle: ResolvedFormID? {
        guard let marker = selectedMarker else { return nil }
        let index = idleControl.indexOfSelectedItem
        return marker.idleIDs.indices.contains(index) ? marker.idleIDs[index] : nil
    }

    /// Rebuilt only when the list changes, so a 2 Hz tick does not close a menu.
    private func reloadMarkers(_ next: [IdleMarkerReadout]) {
        guard next.map(\.reference) != markers.map(\.reference) else {
            markers = next
            return
        }
        let previous = selectedMarker?.reference
        markers = next
        markerControl.removeAllItems()
        markerControl.addItems(withTitles: markers.map { "\($0.editorID) · \($0.reference)" })
        if let index = markers.firstIndex(where: { $0.reference == previous }) {
            markerControl.selectItem(at: index)
        }
        markerControl.isEnabled = !markers.isEmpty
        reloadIdles()
    }

    private func reloadIdles() {
        idleControl.removeAllItems()
        idleControl.addItems(withTitles: selectedMarker?.idles ?? [])
        idleControl.isEnabled = !(selectedMarker?.idles.isEmpty ?? true)
    }

    private func reloadIfLoaded() {
        guard isViewLoaded else { return }
        syncControls()
        refreshReadout()
    }

    // MARK: - Actions

    @objc private func markersToggled() {
        provider?.setUsesIdleMarkers(markersControl.state == .on)
        refreshOverrideState()
        finishInteraction()
    }

    @objc private func markerChanged() {
        reloadIdles()
        syncControls()
        refreshReadout()
        finishInteraction()
    }

    @objc private func idleChanged() {
        syncControls()
        refreshReadout()
        finishInteraction()
    }

    @objc private func fire() {
        guard
            let idle = selectedIdle,
            let actor = selectionProvider?.selectedAIActor else { return }
        provider?.fireIdle(
            idle, on: actor, ignoringConditions: ignoreConditionsControl.state == .on
        )
        refreshReadout()
        finishInteraction()
    }

    @objc private func pick() {
        guard
            let marker = selectedMarker?.reference,
            let actor = selectionProvider?.selectedAIActor
        else { return }
        provider?.pickIdle(at: marker, for: actor)
        refreshReadout()
        finishInteraction()
    }
}
