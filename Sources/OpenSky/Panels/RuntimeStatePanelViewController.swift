// World > Runtime State: the world-state store (docs/engine/runtime-state.md).
// Clock, globals, and conditions are sections here because they inspect the
// same runtime state. Order: store, time, globals, conditions, then the
// change-and-restore sections.

import AppKit
import OpenSkyWorld

final class RuntimeStatePanelViewController: InspectorPanelViewController {
    let inspectSection = RuntimeStateInspectSection()
    let timeSection = RuntimeStateTimeSection()
    let globalsSection = RuntimeStateGlobalsSection()
    let conditionsSection = RuntimeStateConditionsSection()
    let changeSection = RuntimeStateChangeSection()
    let resetSection = RuntimeStateResetSection()
    let saveSection = RuntimeStateSaveSection()

    /// Live world-state bridge. Weak: the game controller owns this panel's
    /// parent and the store, so the panel must not retain back.
    weak var provider: (any RuntimeStateControlProviding)? {
        didSet {
            inspectSection.provider = provider
            timeSection.provider = provider
            globalsSection.provider = provider
            conditionsSection.provider = provider
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
        return [
            inspectSection, timeSection, globalsSection, conditionsSection,
            changeSection, resetSection, saveSection
        ]
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

    var runtimeStateHourControl: NSSlider {
        timeSection.hourControl
    }

    var runtimeStateDayControl: NSTextField {
        timeSection.dayControl
    }

    var runtimeStateMonthControl: NSPopUpButton {
        timeSection.monthControl
    }

    var runtimeStateYearControl: NSTextField {
        timeSection.yearControl
    }

    var runtimeStateApplyDateControl: NSButton {
        timeSection.applyDateControl
    }

    var runtimeStateTimescaleControl: NSTextField {
        timeSection.timescaleControl
    }

    var runtimeStateApplyTimescaleControl: NSButton {
        timeSection.applyTimescaleControl
    }

    var runtimeStateGlobalControl: NSComboBox {
        globalsSection.globalControl
    }

    var runtimeStateGlobalValueControl: NSTextField {
        globalsSection.globalValueControl
    }

    var runtimeStateGlobalApplyControl: NSButton {
        globalsSection.globalApplyControl
    }

    var runtimeStateGlobalResetControl: NSButton {
        globalsSection.globalResetControl
    }

    var runtimeStateConditionSourceControl: NSComboBox {
        conditionsSection.conditionSourceControl
    }

    var runtimeStateConditionEvaluateControl: NSButton {
        conditionsSection.conditionEvaluateControl
    }
}
