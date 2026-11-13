// `RegisterForTrackedStatsEvent` and `OnTrackedStatsEvent(asStat, aiStatValue)`: a
// registered instance hears each misc stat that changed, read from the world-state
// journal. Only the instance that registered hears it (Creation Kit wiki
// "RegisterForTrackedStatsEvent - Form"). See docs/engine/papyrus-registrations.md#tracked-stats.

import Foundation
import OpenSkyQuestsInterface
import OpenSkyScriptingInterface
import OpenSkyWorldState

extension PapyrusWorldRuntime.ScriptEvents {
    /// False when `handle` names no script instance.
    @discardableResult
    func registerTrackedStats(handle: PapyrusObjectHandle, _ isRegistered: Bool) -> Bool {
        guard let key = world.keysByHandle[handle] else { return false }
        if isRegistered {
            world.trackedStatListeners.insert(key)
        } else {
            world.trackedStatListeners.remove(key)
        }
        return true
    }
}

extension PapyrusWorldStateBridge.TrackedStats {
    /// Queues one event per changed stat on each live listener. The first call only sets
    /// the cursor. Returns how many events were queued.
    @discardableResult
    public func queueTrackedStatEvents() -> Int {
        let next = bridge.worldState.nextJournalSequence
        defer { bridge.runState.statsJournalCursor = next }
        guard
            let cursor = bridge.runState.statsJournalCursor, cursor < next,
            let world = bridge.world else { return 0 }
        world.trackedStatListeners = world.trackedStatListeners.filter {
            world.instancesByKey[$0] != nil
        }
        guard !world.trackedStatListeners.isEmpty else { return 0 }
        var changes: [(name: String, value: Int32)] = []
        for entry in bridge.worldState.journalEntries(since: cursor)
            where entry.kind == .miscStats
        {
            let old = entry.oldValue.flatMap(MiscStatsState.init(erased:))?.values ?? [:]
            let new = entry.newValue.flatMap(MiscStatsState.init(erased:))?.values ?? [:]
            for (name, value) in new.sorted(by: { $0.key < $1.key }) where old[name] != value {
                changes.append((name, value))
            }
        }
        let listeners = world.trackedStatListeners.sorted()
        for change in changes {
            for listener in listeners {
                world.enqueue(PapyrusScriptEvent(
                    target: listener,
                    functionName: PapyrusEngineEvents.onTrackedStatsEvent,
                    arguments: [.string(change.name), .integer(change.value)],
                    activationDepth: 0
                ))
            }
        }
        return changes.count * listeners.count
    }

    /// Starts the next read at the journal's end, so a load is not read as stat changes.
    public func skipTrackedStatJournal() {
        bridge.runState.statsJournalCursor = bridge.worldState.nextJournalSequence
    }
}

extension PapyrusNativeFunctions.TrackedStatsNatives {
    static func installTrackedStats(into registry: inout PapyrusNativeRegistry) {
        for script in PapyrusNativeFunctions.UpdateTimersNatives.updateTimerScripts {
            for (name, isRegistered) in [
                ("RegisterForTrackedStatsEvent", true), ("UnregisterForTrackedStatsEvent", false)
            ] {
                registry.register(PapyrusNativeFunction(
                    scriptName: script, functionName: name
                ) { call, context in
                    guard
                        let bridge = context.world as? PapyrusWorldStateBridge,
                        let world = bridge.world, let receiver = call.receiver
                    else { return needsWorld(call) }
                    world.scriptEvents.registerTrackedStats(handle: receiver, isRegistered)
                    return .returned(.none)
                })
            }
        }
    }
}
