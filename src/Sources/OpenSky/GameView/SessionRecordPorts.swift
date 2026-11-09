// The record stores the adapters read, each adapter through its own records port.
// A base of `SessionPorts`, so the composition root stays below the type size limit.

import OpenSkyActorAdapters
import OpenSkyAIAdapters
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyGameData

class SessionRecordPorts {
    unowned let scope: GameSessionScope

    init(scope: GameSessionScope) {
        self.scope = scope
    }

    var worldData: WorldDataStores? {
        scope.worldData
    }

    var worldRecords: (any WorldRecordsPort)? {
        worldData
    }

    var combatRecords: (any CombatRecordsPort)? {
        worldData
    }

    var actorRecords: (any ActorRecordsPort)? {
        worldData
    }

    var aiRecords: (any AIRecordsPort)? {
        worldData
    }
}
