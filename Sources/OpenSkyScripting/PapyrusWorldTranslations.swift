// Scripted moves over time, for `TranslateTo`, with `OnTranslationAlmostComplete`,
// `OnTranslationComplete`, and `OnTranslationFailed`
// (<https://ck.uesp.net/wiki/OnTranslationFailed_-_ObjectReference>). The renderer draws a
// move from the published poses; the store is written once, when it ends, because a
// transform write rebuilds the cell. See docs/engine/papyrus-translation.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface
import OpenSkyWorldInterface
import OpenSkyWorldState

extension PapyrusWorldStateBridge {
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
            let start = referenceState(for: key)?.transform,
            let move = PapyrusTranslation(
                from: start.position, rotation: start.rotation,
                to: target.position, rotation: target.rotation,
                speed: speed, maxRotationSpeed: maxRotationSpeed
            )
        else { return false }
        if translations[key] != nil {
            queueTranslationEvent(PapyrusEngineEvents.onTranslationFailed, on: key)
        }
        translations[key] = move
        sessionNatives.publishTranslationPoses?(translationPoses)
        return true
    }

    /// Leaves the reference where it is now, with no event.
    public func stopTranslation(of key: ReferenceKey) {
        guard let move = translations[key] else { return }
        settle(key, at: move)
    }

    /// Moves every running translation one frame on, in key order. A move whose
    /// reference left the resident cells ends without an event.
    public func advanceTranslations(by seconds: Float) {
        guard !translations.isEmpty else { return }
        for key in translations.keys.sorted() {
            guard var move = translations[key] else { continue }
            guard references?.referenceEntry(key: key) != nil else {
                translations[key] = nil
                continue
            }
            let warned = move.sentAlmostComplete
            let step = move.advance(by: seconds)
            translations[key] = move
            // A frame long enough to finish the move still sends the warning first.
            if step == .almostComplete || (step == .complete && !warned) {
                queueTranslationEvent(PapyrusEngineEvents.onTranslationAlmostComplete, on: key)
            }
            if step == .complete {
                settle(key, at: move)
                queueTranslationEvent(PapyrusEngineEvents.onTranslationComplete, on: key)
            }
        }
        sessionNatives.publishTranslationPoses?(translationPoses)
    }

    /// A loaded game starts with no move running: the save holds none.
    public func clearTranslations() {
        guard !translations.isEmpty else { return }
        translations = [:]
        sessionNatives.publishTranslationPoses?(translationPoses)
    }

    /// Where each moving reference is drawn this frame, without scale.
    public var translationPoses: [ReferenceKey: ReferenceTransformOverride] {
        translations.mapValues { $0.pose(scale: 1) }
    }

    func endTranslation(of key: ReferenceKey) {
        guard translations.removeValue(forKey: key) != nil else { return }
        sessionNatives.publishTranslationPoses?(translationPoses)
    }

    private func settle(_ key: ReferenceKey, at move: PapyrusTranslation) {
        let scale = referenceState(for: key)?.transform.scale ?? 1
        write(move.pose(scale: scale).erased, for: key)
    }

    private func queueTranslationEvent(_ name: String, on key: ReferenceKey) {
        guard let world else { return }
        for instance in world.instanceKeys(on: key) where world.handlesEvent(name, key: instance) {
            world.enqueue(PapyrusScriptEvent(target: instance, functionName: name, arguments: []))
        }
    }
}
