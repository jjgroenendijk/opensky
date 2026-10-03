// World > Inventory & Equipment > Locks: the locks in the loaded cells, a marker
// on the selected one, forced unlock and relock, the key override, and the
// lockpicking menu on demand. Here because the inventory coordinator owns locks.

import AppKit
import OpenSkyFormatsESM
import OpenSkyInventory

final class LockSection: PanelSectionViewController {
    weak var provider: (any LockControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let lockControl = NSPopUpButton()
    let unlockControl = NSButton(title: "Unlock", target: nil, action: nil)
    let relockControl = NSButton(title: "Lock", target: nil, action: nil)
    let pickControl = NSButton(title: "Pick", target: nil, action: nil)
    let carriesKeyControl = NSButton(
        checkboxWithTitle: "Player carries every key",
        target: nil,
        action: nil
    )

    private let statsLabel = PanelComponents.statsLabel(identifier: "LockStatsLabel")
    private var lockIDs: [FormID] = []

    override var sectionTitle: String {
        "Locks"
    }

    override var sectionIdentifier: String {
        "locks"
    }

    var readout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        lockControl.toolTip = "Marks the lock in the world."
        PanelComponents.configurePopUp(
            lockControl, target: self, action: #selector(selectLock),
            identifier: "LockSelectControl", width: 260
        )
        PanelComponents.configureButton(
            unlockControl, target: self, action: #selector(unlock), identifier: "LockUnlockControl"
        )
        PanelComponents.configureButton(
            relockControl, target: self, action: #selector(relock), identifier: "LockRelockControl"
        )
        pickControl.toolTip = "Opens the lockpicking menu on the selected lock."
        PanelComponents.configureButton(
            pickControl, target: self, action: #selector(pick), identifier: "LockPickControl"
        )
        carriesKeyControl.toolTip = "Every lock with a key opens as if the player had it."
        PanelComponents.configureCheckbox(
            carriesKeyControl, target: self, action: #selector(toggleCarriesKey),
            identifier: "LockCarriesKeyControl"
        )
        return [
            PanelComponents.group([
                PanelComponents.labeledFieldRow(
                    caption: "Lock",
                    captionWidth: 60,
                    field: lockControl
                ),
                PanelComponents.buttonRow([unlockControl, relockControl, pickControl]),
                carriesKeyControl
            ]),
            statsLabel
        ]
    }

    override func syncControls() {
        let snapshot = provider?.lockSnapshot ?? .unavailable
        let ids = snapshot.locks.map(\.reference)
        if ids != lockIDs {
            lockIDs = ids
            lockControl.removeAllItems()
            lockControl.addItems(withTitles: snapshot.locks.map(\.title))
        }
        if let selected = snapshot.selected, let index = lockIDs.firstIndex(of: selected) {
            lockControl.selectItem(at: index)
        }
        let hasLocks = !lockIDs.isEmpty
        lockControl.isEnabled = hasLocks
        unlockControl.isEnabled = hasLocks
        relockControl.isEnabled = hasLocks
        pickControl.isEnabled = hasLocks
        carriesKeyControl.isEnabled = snapshot.isAvailable
        carriesKeyControl.state = snapshot.carriesEveryKey ? .on : .off
    }

    override func refreshReadout() {
        syncControls()
        statsLabel.stringValue = LockReadout.text(for: provider?.lockSnapshot ?? .unavailable)
    }

    // MARK: - Actions

    /// The popup's item, selected in the provider before each action.
    private func applySelection() {
        let index = lockControl.indexOfSelectedItem
        provider?.selectLock(lockIDs.indices.contains(index) ? lockIDs[index] : nil)
    }

    @objc private func selectLock() {
        applySelection()
        finishInteraction()
    }

    @objc private func unlock() {
        applySelection()
        provider?.setSelectedLockLocked(false)
        finishInteraction()
    }

    @objc private func relock() {
        applySelection()
        provider?.setSelectedLockLocked(true)
        finishInteraction()
    }

    @objc private func pick() {
        applySelection()
        provider?.pickSelectedLock()
        finishInteraction()
    }

    @objc private func toggleCarriesKey() {
        provider?.setPlayerCarriesEveryKey(carriesKeyControl.state == .on)
        finishInteraction()
    }
}
