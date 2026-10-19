// The AI and perception panels forward to the coordinators that own them.

import OpenSkyAIPackages
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMenus
import OpenSkyPerception
import OpenSkyPerceptionInterface
import OpenSkyRendering

extension GameViewController: AIOverlayControlProviding {
    var navmeshOverlayEnabled: Bool {
        get { renderer?.navmeshOverlayEnabled ?? false }
        set { renderer?.navmeshOverlayEnabled = newValue }
    }

    var pathOverlayEnabled: Bool {
        get { renderer?.pathOverlayEnabled ?? false }
        set { renderer?.pathOverlayEnabled = newValue }
    }

    var detectionOverlayEnabled: Bool {
        get { renderer?.detectionOverlayEnabled ?? false }
        set { renderer?.detectionOverlayEnabled = newValue }
    }

    var aiOverlaySnapshot: AIOverlayControlSnapshot {
        AIOverlayControlSnapshot(
            navmeshOverlayEnabled: navmeshOverlayEnabled,
            pathOverlayEnabled: pathOverlayEnabled,
            detectionOverlayEnabled: detectionOverlayEnabled,
            stats: renderer?.lastWorldOverlayDrawStats ?? WorldOverlayDrawStats()
        )
    }
}

extension GameViewController: AINavigationControlProviding {
    var aiNavigationSnapshot: AINavigationSnapshot {
        aiNavigation.aiNavigationSnapshot
    }

    var selectedAIActor: ReferenceKey? {
        get { aiNavigation.selectedAIActor }
        set { aiNavigation.selectedAIActor = newValue }
    }

    var selectedAIActorIsHostile: Bool {
        get { aiNavigation.selectedAIActorIsHostile }
        set { aiNavigation.selectedAIActorIsHostile = newValue }
    }

    func selectAIActorFromCrosshair() {
        aiNavigation.selectAIActorFromCrosshair()
    }

    func moveSelectedAIActorToCrosshair() {
        aiNavigation.moveSelectedAIActorToCrosshair()
    }

    func stopSelectedAIActor() {
        aiNavigation.stopSelectedAIActor()
    }

    func reevaluateSelectedAIActorPackage() {
        aiNavigation.reevaluateSelectedAIActorPackage()
    }

    func setSelectedAIActorScriptPackage(_ name: String?) {
        aiNavigation.setSelectedAIActorScriptPackage(name)
    }
}

extension GameViewController: PerceptionControlProviding {
    var perceptionSnapshot: PerceptionControlSnapshot {
        perception.perceptionSnapshot
    }

    func perceptionLines(for actor: ReferenceKey) -> [String] {
        perception.perceptionLines(for: actor)
    }
}
