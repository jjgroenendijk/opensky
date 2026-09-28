// World > AI & Navigation > Actor section (issue #203, roadmap item 16.8): the
// one selection every other section under this destination answers for.
//
// A popup of resident actors plus a crosshair pick, which is the same pair
// `World > Container Menu > Merchant` offers and for the same reason: naming a
// reference by FormID is not something a person should have to do, and the
// crosshair is how you point at the one you are actually looking at. The popup
// rebuilds only when the resident list changes, because it ticks at 2 Hz and
// rebuilding it under an open menu would close it in the user's hand.
//
// Not overridden. Which actor you are inspecting is a nomination, not a setting,
// and a "Reset all" that jumped the selection back to the nearest guard would
// lose the one you had been following. The Overlays section owns this
// destination's overridden-ness.

import AppKit

final class AIActorSection: PanelSectionViewController {
    weak var provider: (any AINavigationControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let actorControl = NSPopUpButton()
    let crosshairControl = NSButton(title: "Use crosshair target", target: nil, action: nil)

    private let statsLabel = PanelComponents.statsLabel(identifier: "AIActorStatsLabel")

    /// The options behind the popup's rows, so a selection maps back to a
    /// reference without parsing the title the user sees.
    private var options: [AIActorOption] = []

    override var sectionTitle: String {
        "Actor"
    }

    override var sectionIdentifier: String {
        "aiActor"
    }

    var readout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configurePopUp(
            actorControl, target: self, action: #selector(actorChanged),
            identifier: "AIActorSelectControl", width: PanelMetrics.contentWidth
        )
        PanelComponents.configureButton(
            crosshairControl, target: self, action: #selector(pickFromCrosshair),
            identifier: "AIActorCrosshairControl"
        )
        return [
            PanelComponents.note(
                "Every section below acts on this actor: its mover, its package, what it "
                    + "perceives and where it is in a fight. The list is every actor in the "
                    + "streamed cells, nearest the camera first, named as the Combat & "
                    + "Physics readouts name them. Corpses stay in the list, because "
                    + "selecting one and reading why nothing moves is the answer to a real "
                    + "question."
            ),
            PanelComponents.group([actorControl, crosshairControl]),
            statsLabel
        ]
    }

    override func syncControls() {
        crosshairControl.isEnabled = provider != nil
        reloadOptions()
    }

    override func refreshReadout() {
        guard let snapshot = provider?.aiNavigationSnapshot else {
            statsLabel.stringValue = "Actors: unavailable"
            return
        }
        reloadOptions(snapshot: snapshot)
        statsLabel.stringValue = AINavigationReadout.actorText(for: snapshot)
    }

    /// A popup row names the actor and says whether it is a corpse. It does
    /// *not* carry the distance, deliberately: the list is rebuilt only when its
    /// membership changes, and a number that moves every time the camera does
    /// would either be stale in the row or force a rebuild twice a second that
    /// closed the menu in the user's hand. The live distance is in
    /// `AIActorStatsLabel` below.
    nonisolated static func title(for option: AIActorOption) -> String {
        option.name + (option.isDead ? " · dead" : "")
    }

    // MARK: - Wiring

    private func reloadOptions(snapshot: AINavigationSnapshot? = nil) {
        guard let snapshot = snapshot ?? provider?.aiNavigationSnapshot else {
            options = []
            actorControl.removeAllItems()
            actorControl.isEnabled = false
            return
        }
        // Key order, not the snapshot's nearest-first order. The snapshot sorts
        // by distance because that is what the readout wants; a popup sorted
        // that way would reorder itself as the camera moved, and its rows would
        // change under the cursor twice a second. Membership is what decides a
        // rebuild, and membership only changes when an actor streams in or out.
        let listed = snapshot.actors.sorted { $0.key < $1.key }
        actorControl.isEnabled = !listed.isEmpty
        // Compared as titles rather than as keys, so an actor that dies gets its
        // row relabelled; nothing else in a row can change.
        guard listed.map(Self.title(for:)) != options.map(Self.title(for:)) else {
            options = listed
            selectCurrentActor(snapshot)
            return
        }
        options = listed
        actorControl.removeAllItems()
        actorControl.addItems(withTitles: options.map(Self.title(for:)))
        selectCurrentActor(snapshot)
    }

    private func selectCurrentActor(_ snapshot: AINavigationSnapshot) {
        guard
            let selected = snapshot.selectedActor,
            let index = options.firstIndex(where: { $0.key == selected })
        else { return }
        actorControl.selectItem(at: index)
    }

    // MARK: - Actions

    @objc private func actorChanged() {
        let index = actorControl.indexOfSelectedItem
        guard options.indices.contains(index) else { return }
        provider?.selectedAIActor = options[index].key
        finishInteraction()
    }

    @objc private func pickFromCrosshair() {
        provider?.selectAIActorFromCrosshair()
        syncControls()
        finishInteraction()
    }
}
