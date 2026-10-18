// `RegisterForSleep`, `OnSleepStart(afSleepStartTime, afDesiredSleepEndTime)`, and
// `OnSleepStop(abInterrupted)`. Only the instance that registered hears them (Creation
// Kit wiki "RegisterForSleep - Form"). See docs/engine/papyrus-registrations.md#sleep.

import Foundation
import OpenSkyScriptingInterface

extension PapyrusWorldRuntime {
    /// False when `handle` names no script instance.
    @discardableResult
    public func registerSleep(handle: PapyrusObjectHandle, _ isRegistered: Bool) -> Bool {
        guard let key = keysByHandle[handle] else { return false }
        if isRegistered {
            sleepListeners.insert(key)
        } else {
            sleepListeners.remove(key)
        }
        return true
    }

    /// OpenSky passes the hours at once, so the start and an uninterrupted stop queue
    /// together. Returns how many events were queued.
    @discardableResult
    public func queueSleepEvents(start: Double, end: Double) -> Int {
        sleepListeners = sleepListeners.filter { instancesByKey[$0] != nil }
        let listeners = sleepListeners.sorted()
        for listener in listeners {
            enqueue(PapyrusScriptEvent(
                target: listener, functionName: PapyrusEngineEvents.onSleepStart,
                arguments: [.float(Float(start)), .float(Float(end))], activationDepth: 0
            ))
            enqueue(PapyrusScriptEvent(
                target: listener, functionName: PapyrusEngineEvents.onSleepStop,
                arguments: [.boolean(false)], activationDepth: 0
            ))
        }
        return listeners.count * 2
    }
}

extension PapyrusNativeFunctions {
    static func installSleep(into registry: inout PapyrusNativeRegistry) {
        for script in updateTimerScripts {
            for (name, isRegistered) in [("RegisterForSleep", true), ("UnregisterForSleep", false)] {
                registry.register(PapyrusNativeFunction(
                    scriptName: script, functionName: name
                ) { call, context in
                    guard
                        let bridge = context.world as? PapyrusWorldStateBridge,
                        let world = bridge.world, let receiver = call.receiver
                    else { return needsWorld(call) }
                    world.registerSleep(handle: receiver, isRegistered)
                    return .returned(.none)
                })
            }
        }
    }
}
