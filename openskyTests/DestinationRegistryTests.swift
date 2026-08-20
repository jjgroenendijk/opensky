// The destination registry is the single registration point for main-app
// sidebar destinations (issue #98). These tests pin the UI-test accessibility
// contract (literal ids) as unit assertions — machine-checkable while make
// test-ui is blocked — and verify every world-inspector factory builds a panel.

import AppKit
@testable import opensky
import Testing

struct DestinationRegistryTests {
    @Test @MainActor
    func idsAreUnique() {
        let ids = DestinationRegistry.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test @MainActor
    func registryOrderAndIdentifiers() {
        #expect(DestinationRegistry.all.map(\.id) == [
            "world", "playerLocomotion", "combatPhysics", "aiNavigation", "environment",
            "hudInteraction", "dialogueVoice", "progression", "systemMenu",
            "inventoryMenu", "containerMenu", "inventoryEquipment", "audio",
            "runtimeState", "scripts", "journal", "uiLab", "assetBrowser", "loadOrder"
        ])
        // Accessibility identifiers are the UI-test contract; pin them literally.
        #expect(DestinationRegistry.all.map(\.sidebarIdentifier) == [
            "Destination-world", "Destination-playerLocomotion",
            "Destination-combatPhysics", "Destination-aiNavigation",
            "Destination-environment",
            "Destination-hudInteraction", "Destination-dialogueVoice",
            "Destination-progression", "Destination-systemMenu",
            "Destination-inventoryMenu", "Destination-containerMenu",
            "Destination-inventoryEquipment", "Destination-audio",
            "Destination-runtimeState", "Destination-scripts",
            "Destination-journal", "Destination-uiLab", "Destination-assetBrowser",
            "Destination-loadOrder"
        ])
        #expect(DestinationRegistry.worldInspectors.map(\.id) == [
            "world", "playerLocomotion", "combatPhysics", "aiNavigation", "environment",
            "hudInteraction", "dialogueVoice", "progression", "systemMenu",
            "inventoryMenu", "containerMenu", "inventoryEquipment", "audio",
            "runtimeState", "scripts", "journal", "uiLab"
        ])
        #expect(DestinationRegistry.defaultDestinationID == "world")
    }

    /// No registered destination uses `.viewport` any more — hiding the
    /// inspector column is a View-menu mode, not a sidebar row.
    @Test @MainActor
    func noRegisteredDestinationUsesBareViewport() {
        for descriptor in DestinationRegistry.all {
            if case .viewport = descriptor.content {
                Issue.record("\(descriptor.id) still registers the bare viewport content")
            }
        }
    }

    @Test @MainActor
    func gameViewVisibilityPerContentKind() {
        #expect(DestinationRegistry.destination(id: "world")?.showsGameView == true)
        #expect(DestinationRegistry.destination(id: "environment")?.showsGameView == true)
        #expect(DestinationRegistry.destination(id: "hudInteraction")?.showsGameView == true)
        #expect(DestinationRegistry.destination(id: "assetBrowser")?.showsGameView == false)
        #expect(DestinationRegistry.destination(id: "loadOrder")?.showsGameView == false)
    }

    @Test @MainActor
    func fullContentFactoryBuildsAController() {
        let context = FullContentContext(gameDataRoot: nil, startupErrorMessage: "test")
        for descriptor in DestinationRegistry.all {
            guard case let .fullContent(makeController) = descriptor.content else { continue }
            let controller = makeController(context)
            // Reload must reach the cached controller in place (Settings flow).
            #expect(controller is any FullContentReloadable)
        }
    }

    @Test @MainActor
    func everyWorldInspectorFactoryBuildsAPanel() {
        let providers = FakeWorldProviders()
        let context = WorldPanelContext(providers: providers)
        for descriptor in DestinationRegistry.worldInspectors {
            guard case let .worldInspector(makePanel) = descriptor.content else {
                Issue.record("\(descriptor.id) is not a world inspector")
                continue
            }
            let panel = makePanel(context)
            panel.loadViewIfNeeded()
            #expect(panel.view.frame.width >= 0)
        }
    }

    @Test @MainActor
    func destinationOverrideActionsTrackAndResetProviders() {
        let providers = FakeWorldProviders()
        let context = WorldPanelContext(providers: providers)

        for descriptor in DestinationRegistry.worldInspectors {
            // Progression is the one destination registering no override
            // actions: every control under it writes world state a user
            // produced on purpose, so there is no knob for "Reset all" to
            // restore (DestinationRegistryProgression.swift).
            guard let overrides = descriptor.overrides else {
                #expect(
                    descriptor.id == "progression",
                    "\(descriptor.id) registers no override actions"
                )
                continue
            }
            #expect(!overrides.isOverridden(context), "\(descriptor.id) is not at defaults")
        }

        providers.movementMode = .walk
        #expect(isOverridden("world", context: context))
        reset("world", context: context)
        #expect(providers.movementMode == .fly)

        providers.grassEnabled = false
        #expect(isOverridden("environment", context: context))
        reset("environment", context: context)
        #expect(providers.grassEnabled)

        providers.hudMetersEnabled = false
        #expect(isOverridden("hudInteraction", context: context))
        reset("hudInteraction", context: context)
        #expect(providers.hudMetersEnabled)

        // M17.8: the conversation's own destination. Lip sync off is its
        // settings-shaped override; the reset switches it back on.
        providers.lipSyncEnabled = false
        #expect(isOverridden("dialogueVoice", context: context))
        reset("dialogueVoice", context: context)
        #expect(providers.lipSyncEnabled)

        providers.openSystemMenu()
        #expect(isOverridden("systemMenu", context: context))
        reset("systemMenu", context: context)
        #expect(!providers.systemMenuIsOpen)

        providers.audioEnabled = true
        #expect(isOverridden("audio", context: context))
        reset("audio", context: context)
        #expect(!providers.audioEnabled)

        // M9.2.3: a disabled music director is an audio-destination override,
        // and the destination-level reset re-enables it.
        providers.musicEnabled = false
        #expect(isOverridden("audio", context: context))
        reset("audio", context: context)
        #expect(providers.musicEnabled)

        // M9.2.4: a muted or soloed category is an audio-destination override,
        // and the destination-level reset clears both.
        providers.setAudioCategoryMuted(true, for: .music)
        #expect(isOverridden("audio", context: context))
        reset("audio", context: context)
        #expect(!providers.audioCategoryIsMuted(.music))

        providers.soloedAudioCategory = .voice
        #expect(isOverridden("audio", context: context))
        reset("audio", context: context)
        #expect(providers.soloedAudioCategory == nil)

        providers.uiOverlayEnabled = false
        #expect(isOverridden("uiLab", context: context))
        reset("uiLab", context: context)
        #expect(providers.uiOverlayEnabled)

        #expect(DestinationRegistry.destination(id: "assetBrowser")?.overrides == nil)
    }

    @MainActor
    private func isOverridden(_ id: String, context: WorldPanelContext) -> Bool {
        DestinationRegistry.destination(id: id)?.overrides?.isOverridden(context) ?? false
    }

    @MainActor
    private func reset(_ id: String, context: WorldPanelContext) {
        DestinationRegistry.destination(id: id)?.overrides?.resetToDefaults(context)
    }
}
