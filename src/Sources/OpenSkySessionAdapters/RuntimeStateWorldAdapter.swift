// App side of `RuntimeStateCoordinator`: answers `RuntimeStateWorld` from the
// renderer, the streamer, and the session systems, and runs save and load.
// The rules live in the coordinator (docs/engine/coordinators.md).

public import Foundation
import OpenSkyActorPresentation
public import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyAudio
import OpenSkyCells
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
public protocol RuntimeStateWorldHost: AnyObject, SendableMetatype {
    var dragonFlightWorld: any DragonFlightWorldPort { get }
    var actorValues: any ActorValuePort { get }
    var actorWorld: any ActorWorldPort { get }
    var combat: any CombatPort { get }
    var idleWorld: any IdleWorldPort { get }
    var inventory: any InventoryPort { get }
    var magic: any MagicPort { get }
    var scripts: any ScriptPort { get }
    var streamer: any CellStreamerPort { get }
    var sessionRecords: (any SessionRecordsPort)? { get }
    var worldState: any WorldStateStorePort { get }
}

/// Every host a `RuntimeStateWorldAdapter` part reads, all one object.
public typealias RuntimeStateWorldHosts =
    RuntimeStateConditionReadsHost & RuntimeStateInventoryFactsHost &
    RuntimeStateLiveSeamsHost & RuntimeStateReferenceMotionHost & RuntimeStateSaveContentsHost &
    RuntimeStateSessionClockHost & RuntimeStateSessionLoadHost & RuntimeStateWorldHost

public final class RuntimeStateWorldAdapter {
    public let game: any RuntimeStateWorldHost
    let state = RuntimeStatePartState()
    public let now: () -> Date

    let hosts: any RuntimeStateWorldHosts

    public var core: RuntimeStateCoreAdapter {
        RuntimeStateCoreAdapter(game: game, state: state, inventoryFacts: inventoryFacts)
    }

    public var sessionClock: RuntimeStateSessionClockAdapter {
        RuntimeStateSessionClockAdapter(game: hosts
        )
    }

    public var conditionReads: RuntimeStateConditionReadsAdapter {
        RuntimeStateConditionReadsAdapter(
            game: hosts,
            core: core,
            liveSeams: liveSeams
        )
    }

    public var saveContents: RuntimeStateSaveContentsAdapter {
        RuntimeStateSaveContentsAdapter(
            game: hosts,
            core: core,
            sessionClock: sessionClock,
            now: now
        )
    }

    public var sessionLoad: RuntimeStateSessionLoadAdapter {
        RuntimeStateSessionLoadAdapter(
            game: hosts,
            core: core,
            saveContents: saveContents
        )
    }

    public var liveSeams: RuntimeStateLiveSeamsAdapter {
        RuntimeStateLiveSeamsAdapter(
            game: hosts,
            inventoryFacts: inventoryFacts,
            referenceMotion: referenceMotion
        )
    }

    public var referenceMotion: RuntimeStateReferenceMotionAdapter {
        RuntimeStateReferenceMotionAdapter(game: hosts, state: state)
    }

    public var inventoryFacts: RuntimeStateInventoryFactsAdapter {
        RuntimeStateInventoryFactsAdapter(game: hosts, state: state)
    }

    public init(
        game: some RuntimeStateWorldHosts,
        now: @escaping () -> Date
    ) {
        self.now = now
        hosts = game
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

extension RuntimeStateWorldAdapter: RuntimeStateWorld {}
