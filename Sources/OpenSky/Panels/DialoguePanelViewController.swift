// World > Dialogue & Voice: the conversation loop in one destination, in the
// order a conversation uses it: start, framing, voice, mouth. Each section owns
// its provider seam, sync, and readout, and the four provider types stay
// separate so each dependency is explicit.

import AppKit
import OpenSkyMenus
import OpenSkyWorld

final class DialoguePanelViewController: InspectorPanelViewController {
    let dialogueSection = DialogueSection()
    let dialogueCameraSection = DialogueCameraSection()
    let voiceSection = AudioVoiceSection()
    let faceMorphSection = FaceMorphSection()

    weak var dialogueProvider: (any DialogueControlProviding)? {
        didSet { dialogueSection.provider = dialogueProvider }
    }

    weak var dialogueCameraProvider: (any DialogueCameraControlProviding)? {
        didSet { dialogueCameraSection.provider = dialogueCameraProvider }
    }

    weak var audioProvider: (any AudioControlProviding)? {
        didSet { voiceSection.provider = audioProvider }
    }

    weak var faceMorphProvider: (any FaceMorphControlProviding)? {
        didSet { faceMorphSection.provider = faceMorphProvider }
    }

    override func makeSections() -> [PanelSectionViewController] {
        [dialogueSection, dialogueCameraSection, voiceSection, faceMorphSection]
    }

    /// Control forwards for the verification-surface tests, mirroring the
    /// convention `AudioPanelViewController` set.
    var audioVoiceFilterControl: NSTextField {
        voiceSection.filterControl
    }

    var audioVoiceFileControl: NSPopUpButton {
        voiceSection.fileControl
    }

    var audioVoicePlayControl: NSButton {
        voiceSection.playControl
    }

    var lipSyncEnabledControl: NSButton {
        voiceSection.lipSyncEnabledControl
    }

    var dialogueOpenControl: NSButton {
        dialogueSection.openControl
    }

    var dialogueChooseControl: NSButton {
        dialogueSection.chooseControl
    }

    var faceMorphTargetControl: NSPopUpButton {
        faceMorphSection.targetControl
    }

    var morphWeightControl: NSSlider {
        faceMorphSection.weightControl
    }
}
