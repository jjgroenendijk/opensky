// `RegisterForAnimationEvent` and `OnAnimationEvent`: a script listens for one
// named event that one reference's animation sends, such as `ExitCartEnd`
// (<https://ck.uesp.net/wiki/RegisterForAnimationEvent_-_Form>).

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

extension PapyrusWorldRuntime {
    /// False when `handle` names no script instance.
    @discardableResult
    public func registerAnimationEvent(
        handle: PapyrusObjectHandle, sender: ReferenceKey, name: String
    ) -> Bool {
        guard let key = keysByHandle[handle] else { return false }
        let folded = name.lowercased()
        animationEventListeners[sender, default: [:]][folded, default: []].insert(key)
        if animationEventSpellings[folded] == nil {
            animationEventSpellings[folded] = name
        }
        return true
    }

    public func unregisterAnimationEvent(
        handle: PapyrusObjectHandle, sender: ReferenceKey, name: String
    ) {
        guard let key = keysByHandle[handle] else { return }
        animationEventListeners[sender]?[name.lowercased()]?.remove(key)
    }

    /// Queues `OnAnimationEvent(akSource, asEventName)` on every live listener, in key
    /// order. Returns how many events were queued.
    @discardableResult
    public func queueAnimationEvent(sender: ReferenceKey, name: String) -> Int {
        let listeners = animationEventListeners[sender]?[name.lowercased()] ?? []
        let live = listeners.filter { instancesByKey[$0] != nil }.sorted()
        for key in live {
            enqueue(PapyrusScriptEvent(
                target: key,
                functionName: PapyrusEngineEvents.onAnimationEvent,
                arguments: [.object(objectHandle(for: sender)), .string(name)],
                activationDepth: 0
            ))
        }
        return live.count
    }

    /// The graphs of `senders` unloaded: drops their registrations and queues
    /// `OnAnimationEventUnregistered(akSource, asEventName)` on each live listener
    /// (<https://ck.uesp.net/wiki/OnAnimationEventUnregistered_-_Form>). Returns the count.
    @discardableResult
    func dropAnimationEvents(of senders: some Sequence<ReferenceKey>) -> Int {
        var queued = 0
        for sender in senders.sorted() {
            guard let byName = animationEventListeners.removeValue(forKey: sender) else {
                continue
            }
            for (folded, listeners) in byName.sorted(by: { $0.key < $1.key }) {
                let name = animationEventSpellings[folded] ?? folded
                for key in listeners.sorted() where instancesByKey[key] != nil {
                    enqueue(PapyrusScriptEvent(
                        target: key,
                        functionName: PapyrusEngineEvents.onAnimationEventUnregistered,
                        arguments: [.object(objectHandle(for: sender)), .string(name)],
                        activationDepth: 0
                    ))
                    queued += 1
                }
            }
        }
        return queued
    }
}
