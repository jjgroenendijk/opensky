// World > Runtime State destination panel (M10.1.5): the sidebar verification
// surface for the world-state store. Thin composition of four self-contained
// sections — inspect, change, reset, save and load — on the shared panel
// framework, the same shape as AudioPanelViewController. Exact sidebar path and
// control ids: docs/engine/runtime-state.md.

import AppKit

final class RuntimeStatePanelViewController: InspectorPanelViewController {
    let inspectSection = RuntimeStateInspectSection()
    let changeSection = RuntimeStateChangeSection()
    let resetSection = RuntimeStateResetSection()
    let saveSection = RuntimeStateSaveSection()

    /// Live world-state bridge. Weak: the game controller owns this panel's
    /// parent and the store, so the panel must not retain back.
    weak var provider: (any RuntimeStateControlProviding)? {
        didSet {
            inspectSection.provider = provider
            changeSection.provider = provider
            resetSection.provider = provider
            saveSection.provider = provider
        }
    }

    override func makeSections() -> [PanelSectionViewController] {
        // The Change section owns the one target field; Reset reads it so both
        // act on the same reference.
        resetSection.targetSelectorSource = { [weak changeSection] in
            changeSection?.targetSelector ?? .currentTarget
        }
        return [inspectSection, changeSection, resetSection, saveSection]
    }

    /// Control forwards for the verification-surface tests, mirroring
    /// AudioPanelViewController's convention.
    var runtimeStateTargetControl: NSTextField {
        changeSection.targetControl
    }

    var runtimeStateDisableControl: NSButton {
        changeSection.disableControl
    }

    var runtimeStateEnableControl: NSButton {
        changeSection.enableControl
    }

    var runtimeStateNudgeControl: NSButton {
        changeSection.nudgeControl
    }

    var runtimeStateResetTargetControl: NSButton {
        resetSection.resetTargetControl
    }

    var runtimeStateResetAllControl: NSButton {
        resetSection.resetAllControl
    }

    var runtimeStateSlotControl: NSTextField {
        saveSection.slotControl
    }

    var runtimeStateSaveControl: NSButton {
        saveSection.saveControl
    }

    var runtimeStateLoadControl: NSButton {
        saveSection.loadControl
    }
}
