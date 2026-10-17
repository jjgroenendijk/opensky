// `OnGainLOS` and `OnLostLOS` for the registrations in `LineOfSightWatch`. Only the
// instance that registered hears the event (Creation Kit wiki "RegisterForLOS - Form").
// See docs/engine/papyrus-registrations.md#line-of-sight.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

extension PapyrusWorldRuntime {
    /// Registers, or with a nil `mode` unregisters, the instance behind `handle`. False
    /// when `handle` names no script instance.
    @discardableResult
    public func registerLineOfSight(
        handle: PapyrusObjectHandle, pair: LineOfSightWatch.Pair, mode: LineOfSightWatch.Mode?
    ) -> Bool {
        guard let key = keysByHandle[handle] else { return false }
        if let mode {
            lineOfSight.register(key, pair, mode: mode)
        } else {
            lineOfSight.unregister(key, pair)
        }
        return true
    }

    /// Checks every registered pair once and queues the events. Returns how many.
    @discardableResult
    public func queueLineOfSightEvents(sees: (LineOfSightWatch.Pair) -> Bool?) -> Int {
        guard !lineOfSight.isEmpty else { return 0 }
        let events = lineOfSight.step(isLive: { instancesByKey[$0] != nil }, sees: sees)
        for event in events {
            enqueue(PapyrusScriptEvent(
                target: event.instance,
                functionName: event.gained
                    ? PapyrusEngineEvents.onGainLOS : PapyrusEngineEvents.onLostLOS,
                arguments: [
                    .object(objectHandle(for: event.pair.viewer)),
                    .object(objectHandle(for: event.pair.target))
                ],
                activationDepth: 0
            ))
        }
        return events.count
    }
}

extension PapyrusWorldStateBridge {
    /// Queues the line-of-sight events through the `seesTarget` seam. No seam, no events.
    @discardableResult
    public func queueLineOfSightEvents() -> Int {
        guard let world, let seesTarget = perceptionNatives.seesTarget else { return 0 }
        return world.queueLineOfSightEvents { seesTarget($0.viewer, $0.target) }
    }
}

extension PapyrusNativeFunctions {
    /// The same four natives on `Form`, `Alias`, and `ActiveMagicEffect`.
    static func installLineOfSight(into registry: inout PapyrusNativeRegistry) {
        let natives: [(String, LineOfSightWatch.Mode?)] = [
            ("RegisterForLOS", .both),
            ("RegisterForSingleLOSGain", .singleGain),
            ("RegisterForSingleLOSLost", .singleLost),
            ("UnregisterForLOS", nil)
        ]
        for script in updateTimerScripts {
            for (name, mode) in natives {
                registry.register(PapyrusNativeFunction(
                    scriptName: script, functionName: name
                ) { call, context in
                    guard
                        let bridge = context.world as? PapyrusWorldStateBridge,
                        let world = bridge.world, let receiver = call.receiver
                    else { return needsWorld(call) }
                    guard
                        let viewer = objectArgument(call, at: 0).flatMap(bridge.referenceKey(for:)),
                        let target = objectArgument(call, at: 1).flatMap(bridge.referenceKey(for:))
                    else { return failure(call, "\(name) needs a viewer and a target") }
                    let pair = LineOfSightWatch.Pair(viewer: viewer, target: target)
                    world.registerLineOfSight(handle: receiver, pair: pair, mode: mode)
                    return .returned(.none)
                })
            }
        }
    }
}
