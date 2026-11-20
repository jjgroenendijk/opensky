// Scripted moves over time, for `TranslateTo`, with `OnTranslationAlmostComplete`,
// `OnTranslationComplete`, and `OnTranslationFailed`
// (<https://ck.uesp.net/wiki/OnTranslationFailed_-_ObjectReference>). The renderer draws a
// move from the published poses; the store is written once, when it ends, because a
// transform write rebuilds the cell. See docs/engine/papyrus-translation.md.

import Foundation
public import OpenSkyFormatsESM
public import OpenSkyScriptingInterface
import OpenSkyWorldInterface
import OpenSkyWorldState

extension PapyrusWorldStateBridge.ScriptedMoves {
    /// Starts a move from where `key` is now. A move already running fails first. False
    /// for a reference no resident cell holds, or for a speed that is not above zero.
    @discardableResult
    public func startTranslation(
        of key: ReferenceKey,
        to target: ReferenceTransformOverride,
        speed: Float,
        maxRotationSpeed: Float
    ) -> Bool {
        guard
            let start = bridge.referenceState(for: key)?.transform,
            let move = PapyrusTranslation(
                from: start.position, rotation: start.rotation,
                to: target.position, rotation: target.rotation,
                speed: speed, maxRotationSpeed: maxRotationSpeed
            )
        else { return false }
        if bridge.runState.translations[key] != nil {
            queueTranslationEvent(PapyrusEngineEvents.onTranslationFailed, on: key)
        }
        bridge.runState.translations[key] = move
        bridge.natives.session.publishTranslationPoses?(translationPoses)
        return true
    }

    /// Leaves the reference where it is now, with no event.
    public func stopTranslation(of key: ReferenceKey) {
        bridge.runState.pendingTranslations[key] = nil
        guard let move = bridge.runState.translations[key] else { return }
        settle(key, at: move)
    }

    /// Moves every running translation one frame on, in key order. A move whose
    /// reference left the resident cells ends without an event.
    public func advanceTranslations(by seconds: Float) {
        resumePendingTranslations()
        guard !bridge.runState.translations.isEmpty else { return }
        for key in bridge.runState.translations.keys.sorted() {
            guard var move = bridge.runState.translations[key] else { continue }
            guard bridge.ports.references?.referenceEntry(key: key) != nil else {
                bridge.runState.translations[key] = nil
                continue
            }
            let warned = move.sentAlmostComplete
            let step = move.advance(by: seconds)
            bridge.runState.translations[key] = move
            // A frame long enough to finish the move still sends the warning first.
            if step == .almostComplete || (step == .complete && !warned) {
                queueTranslationEvent(PapyrusEngineEvents.onTranslationAlmostComplete, on: key)
            }
            if step == .complete {
                settle(key, at: move)
                queueTranslationEvent(PapyrusEngineEvents.onTranslationComplete, on: key)
            }
        }
        bridge.natives.session.publishTranslationPoses?(translationPoses)
    }

    /// A loaded game first drops the moves of the session it replaces.
    public func clearTranslations() {
        bridge.runState.pendingTranslations = [:]
        guard !bridge.runState.translations.isEmpty else { return }
        bridge.runState.translations = [:]
        bridge.natives.session.publishTranslationPoses?(translationPoses)
    }

    /// Every move a save keeps, running or still waiting for its cell.
    public func savedTranslations() -> [ReferenceKey: SavedTranslation] {
        bridge.runState.pendingTranslations.merging(bridge.runState.translations) { _, running in
            running
        }.mapValues(\.saved)
    }

    /// The moves a save kept. Each goes on once a resident cell holds its reference.
    public func restoreTranslations(_ saved: [ReferenceKey: SavedTranslation]) {
        clearTranslations()
        bridge.runState.pendingTranslations = saved
            .compactMapValues(PapyrusTranslation.init(saved:))
        resumePendingTranslations()
    }

    private func resumePendingTranslations() {
        guard !bridge.runState.pendingTranslations.isEmpty else { return }
        var resumed = false
        for key in bridge.runState.pendingTranslations.keys.sorted()
            where bridge.ports.references?.referenceEntry(key: key) != nil
        {
            bridge.runState.translations[key] = bridge.runState.pendingTranslations
                .removeValue(forKey: key)
            resumed = true
        }
        if resumed {
            bridge.natives.session.publishTranslationPoses?(translationPoses)
        }
    }

    /// Where each moving reference is drawn this frame, without scale.
    public var translationPoses: [ReferenceKey: ReferenceTransformOverride] {
        bridge.runState.translations.mapValues { $0.pose(scale: 1) }
    }

    func endTranslation(of key: ReferenceKey) {
        bridge.runState.pendingTranslations[key] = nil
        guard bridge.runState.translations.removeValue(forKey: key) != nil else { return }
        bridge.natives.session.publishTranslationPoses?(translationPoses)
    }

    private func settle(_ key: ReferenceKey, at move: PapyrusTranslation) {
        let scale = bridge.referenceState(for: key)?.transform.scale ?? 1
        bridge.write(move.pose(scale: scale).erased, for: key)
    }

    private func queueTranslationEvent(_ name: String, on key: ReferenceKey) {
        guard let world = bridge.world else { return }
        for instance in world.instanceKeys(on: key) where world.scriptEvents.handlesEvent(
            name,
            key: instance
        ) {
            world.enqueue(PapyrusScriptEvent(target: instance, functionName: name, arguments: []))
        }
    }
}

extension PapyrusWorldStateBridge {
    /// Every scripted move a save keeps.
    public func savedTranslations() -> [ReferenceKey: SavedTranslation] {
        scriptedMoves.savedTranslations()
    }

    /// Starts a move to `position` that keeps the reference's rotation. False for a
    /// reference no resident cell holds.
    public func translate(_ key: ReferenceKey, to position: SIMD3<Float>, speed: Float) -> Bool {
        guard let rotation = referenceState(for: key)?.transform.rotation else { return false }
        return scriptedMoves.startTranslation(
            of: key, to: ReferenceTransformOverride(position: position, rotation: rotation),
            speed: speed, maxRotationSpeed: 0
        )
    }

    /// The scripted moves a save kept, after the scripts are restored.
    public func restoreTranslations(_ saved: [ReferenceKey: SavedTranslation]) {
        scriptedMoves.restoreTranslations(saved)
    }
}
