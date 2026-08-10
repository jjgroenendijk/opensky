// World > HUD & Interaction > Dialogue Camera section coverage (issue #427).
// Synthetic provider state only; the pixel half of the gate is
// `DialogueCameraRenderRealDataTests` and the framing math is
// `DialogueCameraTests`.
//
// Two things are pinned here and nowhere else: the accessibility ids, which are
// the UI-test API and must never change silently, and the readout wording,
// which is how the milestone's acceptance question — "did leaving a
// conversation give the previous camera back" — is answered from a readout
// rather than by eye.

import AppKit
@testable import opensky
import simd
import Testing

@MainActor
struct DialogueCameraSectionTests {
    private func makePanel(
        _ provider: FakeWorldProviders
    ) -> HUDInteractionPanelViewController {
        let panel = HUDInteractionPanelViewController()
        panel.provider = provider
        panel.itemProvider = provider
        panel.dialogueProvider = provider
        panel.dialogueCameraProvider = provider
        panel.loadViewIfNeeded()
        return panel
    }

    @Test
    func controlsExposeStableIdentifiers() {
        let provider = FakeWorldProviders()
        let section = makePanel(provider).dialogueCameraSection
        let controls: [(NSControl, String)] = [
            (section.forceControl, "DialogueCameraForceControl"),
            (section.targetControl, "DialogueCameraTargetControl"),
            (section.overlayControl, "DialogueCameraOverlayControl")
        ]
        for (control, identifier) in controls {
            #expect(control.accessibilityIdentifier() == identifier)
        }
        #expect(section.sectionIdentifier == "dialogueCamera")
        #expect(section.sectionTitle == "Dialogue Camera")
    }

    /// Every control reaches the provider, and the target popup lists exactly
    /// the selectors the seam declares.
    @Test
    func theControlsDriveTheProviderSeam() {
        let provider = FakeWorldProviders()
        let section = makePanel(provider).dialogueCameraSection

        // Controls are driven with `sendAction`, never `performClick`: clicking
        // an `NSPopUpButton` opens its menu and blocks in a modal tracking loop
        // that never returns without a pointer, which hangs the whole run.
        section.forceControl.state = .on
        sendScriptsControl(section.forceControl)
        #expect(provider.isDialogueCameraForced)

        section.overlayControl.state = .on
        sendScriptsControl(section.overlayControl)
        #expect(provider.dialogueCameraOverlayEnabled)

        #expect(section.targetControl.numberOfItems == DialogueCameraTarget.allCases.count)
        section.targetControl.selectItem(
            at: DialogueCameraSection.targets.firstIndex(of: .nearestActor) ?? 0
        )
        sendScriptsControl(section.targetControl)
        #expect(provider.dialogueCameraTarget == .nearestActor)
    }

    /// Both switches default off, so either one being on is what "Reset all"
    /// undoes. An engaged camera is not: the conversation owns it, and a reset
    /// that ended a conversation would be a reset that closed a menu.
    @Test
    func onlyTheSwitchesCountAsOverridden() {
        let provider = FakeWorldProviders()
        _ = makePanel(provider)
        #expect(!DialogueCameraSection.isOverridden(provider: provider))

        provider.dialogueCamera.snapshot = makeDialogueCameraSnapshot(isEngaged: true)
        #expect(!DialogueCameraSection.isOverridden(provider: provider))

        provider.isDialogueCameraForced = true
        provider.dialogueCameraOverlayEnabled = true
        #expect(DialogueCameraSection.isOverridden(provider: provider))
        DialogueCameraSection.resetToDefaults(provider: provider)
        #expect(!provider.isDialogueCameraForced)
        #expect(!provider.dialogueCameraOverlayEnabled)
    }

    // MARK: - Readout

    @Test
    func aReleasedCameraSaysWhatItWouldGoBackTo() {
        let text = DialogueCameraReadout.cameraText(for: makeDialogueCameraSnapshot(
            restoreMode: .walk, restoreFOVYDegrees: 95
        ))
        #expect(text.contains("Dialogue camera: released"))
        #expect(text.contains("Restores: walk at 95 degrees"))
        #expect(text.contains("Framing: not resolved"))
    }

    @Test
    func anEngagedCameraNamesTheSpeakerThePivotAndTheSqueeze() {
        let text = DialogueCameraReadout.cameraText(for: makeDialogueCameraSnapshot(
            isEngaged: true,
            speakerName: "Lucan Valerius",
            pose: makeDialogueCameraPose(isCollisionLimited: true)
        ))
        #expect(text.contains("engaged on Lucan Valerius"))
        #expect(text.contains("Pivot: (0, 0, 112)"))
        #expect(text.contains("eye: (126, 24, 112)"))
        #expect(text.contains("128 units, pulled in by geometry"))
        #expect(text.contains("65 degrees while engaged"))
    }

    @Test
    func theSpeakerReadoutStatesTheTurnAndTheHeldPackage() {
        let empty = DialogueCameraReadout.speakerText(for: makeDialogueCameraSnapshot())
        #expect(empty == "Speaker focus: nobody held")

        let text = DialogueCameraReadout.speakerText(for: makeDialogueCameraSnapshot(
            speakerFocus: DialogueSpeakerFocusRow(
                movementState: "turning",
                yawDegrees: 30,
                targetYawDegrees: 90,
                isSettled: false,
                isPackageSuspended: true,
                packageEditorID: "MerchantRiverwoodTraderLucan"
            )
        ))
        #expect(text.contains("turning to face the player"))
        #expect(text.contains("movement turning"))
        #expect(text.contains("Yaw: 30 of 90 degrees"))
        #expect(text.contains("package MerchantRiverwoodTraderLucan suspended"))
    }

    /// Without a renderer the readout says so, rather than reporting a camera
    /// that is merely disengaged.
    @Test
    func noRendererIsStatedRatherThanShownAsReleased() {
        let text = DialogueCameraReadout.cameraText(for: .empty)
        #expect(text == "Dialogue camera: unavailable (no renderer)")
        #expect(
            DialogueCameraReadout.speakerText(for: .empty)
                == "Speaker focus: unavailable (no renderer)"
        )
        #expect(
            DialogueCameraReadout.outcomeText(for: .empty)
                == "Open a conversation, or force the camera onto the selected actor."
        )
    }
}
