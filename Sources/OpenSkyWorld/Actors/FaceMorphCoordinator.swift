// The Face Morphs panel, and the automatic face of every loaded actor: blinking and
// the emotion of the line a speaker says. See docs/engine/coordinators.md.

import OpenSkyFormatsESM
import OpenSkyGameData

/// What `FaceMorphCoordinator` reads from the running world.
public protocol FaceMorphWorld: AnyObject {
    /// The speaker, else the actor the Talk prompt targets.
    var faceMorphSubject: FormID? { get }
    func faceMorphPlayback(for actor: FormID) -> FaceMorphPlayback?
    /// Every loaded face, for blinking.
    var faceMorphPlaybacks: [FaceMorphPlayback] { get }
}

public final class FaceMorphCoordinator {
    /// An emotion on one face, until an animation time, or until cleared.
    private struct HeldEmotion {
        let weights: [String: Float]
        let until: Float?
    }

    weak var world: (any FaceMorphWorld)?
    public var automaticBlinkingEnabled = true
    public var dialogueExpressionsEnabled = true
    private var emotions: [FormID: HeldEmotion] = [:]

    /// `settings` gives the persisted blinking and expression switches.
    public init(world: (any FaceMorphWorld)? = nil, settings: PlayerSettingsStore? = nil) {
        self.world = world
        if let settings {
            automaticBlinkingEnabled = settings.bool(.characterBlinking)
            dialogueExpressionsEnabled = settings.bool(.characterDialogueExpressions)
        }
    }

    public func attach(world: any FaceMorphWorld) {
        self.world = world
    }

    private var selectedPlayback: FaceMorphPlayback? {
        guard let world, let actor = world.faceMorphSubject else { return nil }
        return world.faceMorphPlayback(for: actor)
    }

    /// Shows `emotion` on `actor`'s face. With `seconds`, it ends on its own.
    public func showEmotion(
        _ emotion: TopicInfo.Response.Emotion, value: UInt32, on actor: FormID,
        now: Float, seconds: Float? = nil
    ) {
        emotions[actor] = HeldEmotion(
            weights: FacialExpressionCore.emotionWeights(emotion, value: value),
            until: seconds.map { now + max($0, 0) }
        )
    }

    public func clearEmotion(on actor: FormID) {
        emotions[actor] = nil
    }

    /// Sets every loaded face's automatic weights for animation time `now`.
    public func tick(now: Float) {
        emotions = emotions.filter { $0.value.until.map { $0 > now } ?? true }
        for playback in world?.faceMorphPlaybacks ?? [] {
            let emotion = dialogueExpressionsEnabled
                ? emotions[playback.actor]?.weights ?? [:] : [:]
            let blink = automaticBlinkingEnabled
                ? FacialExpressionCore.blink(at: now, seed: playback.actor.rawValue) : 0
            playback.setExpressionWeights(
                FacialExpressionCore.weights(emotion: emotion, blink: blink)
            )
        }
    }
}

extension FaceMorphCoordinator {
    public var faceMorphSnapshot: FaceMorphControlSnapshot {
        guard let playback = selectedPlayback else { return .empty }
        return FaceMorphControlSnapshot(
            actor: playback.actor,
            targetNames: playback.targetNames,
            weights: playback.weights,
            pairedPaths: playback.pairedPaths,
            associationMisses: playback.misses.map { "\($0.headPart): \($0.reason)" },
            unknownTargetCount: playback.unknownTargetCount,
            expressionWeights: playback.expressionWeights
        )
    }

    public func setFaceMorphWeight(_ weight: Float, target: String) {
        selectedPlayback?.setWeight(weight, for: target)
    }

    public func resetFaceMorphWeights() {
        selectedPlayback?.resetToBindPose()
    }
}
