// The live condition context builds each view at its first read. These tests read
// every deferred view once, against a session with no game loaded.

import Foundation
import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyDialogueInterface
import OpenSkyFactionsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyPerceptionInterface
import OpenSkyScriptingInterface
import OpenSkySessionAdapters
import OpenSkySessionTesting
import OpenSkyWorldConditionFunctions
import OpenSkyWorldInterface
import OpenSkyWorldState
import Testing

@MainActor
struct RuntimeStateDeferredSeamsTests {
    private let host = SessionHost()

    private func context() -> ConditionContext {
        host.fakeStreamer.residents.residentReferencePlacesResult = ReferencePlaces()
        host.fakePerception.perceptionResolutionResult = .empty
        host.fakeCrime.conditionResolutionResult = .empty
        host.fakeFactions.conditionResolutionResult = .empty
        host.fakeActorGraphWorld.graphVariableResolutionResult = .empty
        host.fakeMagic.magicConditionResolutionResult = .empty
        host.fakeScenes.conditionResolutionResult = .empty
        (host.fakeIdleWorld.idles as? FakeIdlePort)?.furnitureResolutionValue = .empty
        let world = RuntimeStateWorldAdapter(
            game: host, now: { Date(timeIntervalSinceReferenceDate: 0) }
        )
        return world.conditionContext(crosshair: nil, globals: .empty, indexing: [])
    }

    @Test func theScriptSceneAndWorldViewsBuildWhenRead() {
        let context = context()
        _ = context[resolution: ScriptVariableResolution.self]
        _ = context[resolution: ScriptedStateConditionResolution.self]
        _ = context[resolution: SceneConditionResolution.self]
        _ = context[resolution: WeatherConditionResolution.self]
        _ = context[resolution: FurnitureConditionResolution.self]
        _ = context[resolution: GraphVariableResolution.self]
        #expect(context[resolution: MenuConditionResolution.self].isMenuOpen == false)
        #expect(context[resolution: DialogueResolution.self].speakerInDialogue == nil)
    }

    @Test func theCrimeFactionAndInventoryViewsBuildWhenRead() {
        let context = context()
        #expect(context[resolution: CrimeConditionResolution.self].situation?
            .trespassWarnings.isEmpty != false)
        _ = context[resolution: FactionConditionResolution.self]
        _ = context[resolution: InventoryConditionResolution.self]
        _ = context[resolution: PackageConditionResolution.self]
    }

    @Test func theReferenceViewsBuildWhenRead() {
        let context = context()
        _ = context[resolution: MotionConditionResolution.self]
        _ = context[resolution: PlaceConditionResolution.self]
        #expect(context.data.keywords == nil)
    }
}
