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
        animationEventListeners[sender, default: [:]][name.lowercased(), default: []].insert(key)
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
                functionName: Self.onAnimationEventName,
                arguments: [.object(objectHandle(for: sender)), .string(name)],
                activationDepth: 0
            ))
        }
        return live.count
    }
}
