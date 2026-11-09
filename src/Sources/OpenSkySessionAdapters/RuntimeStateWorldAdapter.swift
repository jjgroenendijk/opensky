// App side of `RuntimeStateCoordinator`: answers `RuntimeStateWorld` from the
// renderer, the streamer, and the session systems, and runs save and load.
// The rules live in the coordinator (docs/engine/coordinators.md).

import Foundation
import OpenSkyActorPresentation
public import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyAudio
public import OpenSkyCells
import OpenSkyCombatInterface
public import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyDialogueInterface
import OpenSkyFactionsInterface
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyPerceptionInterface
import OpenSkyPlayer
import OpenSkyQuestsInterface
import OpenSkyRenderCore
import OpenSkyRendering
public import OpenSkyRuntimeState
import OpenSkySave
import OpenSkySaveInterface
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWeather
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `RuntimeStateWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
public protocol RuntimeStateWorldHost: AnyObject {
    var dragonFlightWorld: any DragonFlightWorldPort { get }
    var actorValues: any ActorValuePort { get }
    var actorWorld: any ActorWorldPort { get }
    var combat: any CombatPort { get }
    var idleWorld: any IdleWorldPort { get }
    var inventory: any InventoryPort { get }
    var magic: any MagicPort { get }
    var scripts: any ScriptPort { get }
    var streamer: (any CellStreamerPort)? { get }
    var worldData: WorldDataStores? { get }
    var worldState: any WorldStateStorePort { get }
}

public final class RuntimeStateWorldAdapter {
    public let game: any RuntimeStateWorldHost
    public let state = RuntimeStatePartState()

    public let sessionClockHost: any RuntimeStateSessionClockHost
    public let conditionReadsHost: any RuntimeStateConditionReadsHost
    public let saveContentsHost: any RuntimeStateSaveContentsHost
    public let sessionLoadHost: any RuntimeStateSessionLoadHost
    public let liveSeamsHost: any RuntimeStateLiveSeamsHost
    public let referenceMotionHost: any RuntimeStateReferenceMotionHost
    public let inventoryFactsHost: any RuntimeStateInventoryFactsHost

    public var core: RuntimeStateCoreAdapter {
        RuntimeStateCoreAdapter(game: game, state: state, inventoryFacts: inventoryFacts)
    }

    public var sessionClock: RuntimeStateSessionClockAdapter {
        RuntimeStateSessionClockAdapter(game: sessionClockHost
        )
    }

    public var conditionReads: RuntimeStateConditionReadsAdapter {
        RuntimeStateConditionReadsAdapter(
            game: conditionReadsHost,
            core: core,
            liveSeams: liveSeams
        )
    }

    public var saveContents: RuntimeStateSaveContentsAdapter {
        RuntimeStateSaveContentsAdapter(
            game: saveContentsHost,
            core: core,
            sessionClock: sessionClock
        )
    }

    public var sessionLoad: RuntimeStateSessionLoadAdapter {
        RuntimeStateSessionLoadAdapter(
            game: sessionLoadHost,
            core: core,
            saveContents: saveContents
        )
    }

    public var liveSeams: RuntimeStateLiveSeamsAdapter {
        RuntimeStateLiveSeamsAdapter(
            game: liveSeamsHost,
            inventoryFacts: inventoryFacts,
            referenceMotion: referenceMotion
        )
    }

    public var referenceMotion: RuntimeStateReferenceMotionAdapter {
        RuntimeStateReferenceMotionAdapter(game: referenceMotionHost, state: state)
    }

    public var inventoryFacts: RuntimeStateInventoryFactsAdapter {
        RuntimeStateInventoryFactsAdapter(game: inventoryFactsHost, state: state)
    }

    public init(game: some RuntimeStateWorldHost & RuntimeStateSessionClockHost &
        RuntimeStateConditionReadsHost & RuntimeStateSaveContentsHost &
        RuntimeStateSessionLoadHost &
        RuntimeStateLiveSeamsHost & RuntimeStateReferenceMotionHost &
        RuntimeStateInventoryFactsHost)
    {
        sessionClockHost = game
        conditionReadsHost = game
        saveContentsHost = game
        sessionLoadHost = game
        liveSeamsHost = game
        referenceMotionHost = game
        inventoryFactsHost = game
        self.game = game
    }
}

extension RuntimeStateWorldAdapter {
    public func actorResolution() -> ActorStateResolution {
        core.actorResolution()
    }

    public func conditionData() -> ConditionDataResolution {
        core.conditionData()
    }

    public func location(of key: CellLocationKey) -> ResolvedFormID? {
        core.location(of: key)
    }

    public func locationMusicType(of scene: CellLocationKey) -> FormID? {
        core.locationMusicType(of: scene)
    }
}

extension RuntimeStateWorldAdapter: RuntimeStateWorld {
    public var conditionFunctions: ConditionFunctionRegistry {
        .standard
    }
}
