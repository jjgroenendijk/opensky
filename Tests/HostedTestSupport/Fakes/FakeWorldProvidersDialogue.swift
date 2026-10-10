// `FakeWorldProviders`' DialogueControlProviding and
// DialogueCameraControlProviding forwarding. Both test targets share the fake,
// so its conformances are shared too (Tests/HostedTestSupport/AGENTS.md).

import AppKit
@testable import OpenSkyMenus

/// Forwards the dialogue seam to the panel tests' recorder rather than
/// duplicating it, so a registry-level reset and a panel-level button click are
/// observed through the same fake.
extension FakeWorldProviders {
    var dialogueSnapshot: DialogueControlSnapshot {
        dialogue.dialogueSnapshot
    }

    func openDialogue() {
        dialogue.openDialogue()
    }

    func closeDialogue() {
        dialogue.closeDialogue()
    }

    func sendDialogueInput(_ event: MenuInputEvent) {
        dialogue.sendDialogueInput(event)
    }
}

/// The same forwarding for the conversation camera.
extension FakeWorldProviders {
    var dialogueCameraSnapshot: DialogueCameraSnapshot {
        dialogueCamera.dialogueCameraSnapshot
    }

    var isDialogueCameraForced: Bool {
        get { dialogueCamera.isDialogueCameraForced }
        set { dialogueCamera.isDialogueCameraForced = newValue }
    }

    var dialogueCameraTarget: DialogueCameraTarget {
        get { dialogueCamera.dialogueCameraTarget }
        set { dialogueCamera.dialogueCameraTarget = newValue }
    }

    var dialogueCameraOverlayEnabled: Bool {
        get { dialogueCamera.dialogueCameraOverlayEnabled }
        set { dialogueCamera.dialogueCameraOverlayEnabled = newValue }
    }
}
