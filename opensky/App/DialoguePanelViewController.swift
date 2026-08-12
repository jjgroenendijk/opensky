// World > Dialogue & Voice: the M17 milestone's own destination (issue #209).
//
// The four sections the milestone's sub-issues delivered were mounted where
// their nearest neighbour already lived — the conversation and the face under
// `World > HUD & Interaction` because that is where the crosshair is, the voice
// line under `World > Audio` because that is where the submixes are. A
// conversation is one loop across all of them, so the gate assembles them into
// one destination in the order a conversation uses them: start it, see it
// framed, hear it, watch the mouth move.
//
// Each section is standalone — it owns its provider seam, its sync and its
// readout — so this assembly changed no control identifier. Four provider types
// rather than one: the sections read the dialogue runtime, the dialogue camera,
// the face-morph playback and the world audio engine, and typing them apart
// keeps each section's dependency honest.

import AppKit

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

    var dialogueLeaveControl: NSButton {
        dialogueSection.leaveControl
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
