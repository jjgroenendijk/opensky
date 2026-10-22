// The Face Morphs panel, and the automatic face of every loaded actor: blinking, eye
// drift, and the emotion of the line a speaker says. See docs/engine/face-morphs.md.

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
        let emotion: TopicInfo.Response.Emotion
        let weights: [String: Float]
        let until: Float?
    }

    /// One face's automatic state between frames.
    private struct FaceState {
        var nextBlink: Float
        var blinkStart: Float?
        /// The emotion weights on screen, easing toward the held emotion.
        var shown: [String: Float] = [:]
        /// Emotion weight per second of the latest change.
        var rate: Float = .infinity
    }

    weak let world: (any FaceMorphWorld)?
    public var settings = FaceAnimationSettings.vanilla
    public var automaticBlinkingEnabled = true
    public var dialogueExpressionsEnabled = true
    public var eyeMovementEnabled = true
    /// A number in 0 ..< 1 for blink gaps and emotion change speeds. A test fixes it.
    public var random: () -> Float = { Float.random(in: 0 ..< 1) }
    private var emotions: [FormID: HeldEmotion] = [:]
    private var faces: [FormID: FaceState] = [:]
    private var lastTick: Float?

    /// `settings` gives the persisted blinking, expression, and eye switches.
    public init(world: (any FaceMorphWorld)? = nil, settings: PlayerSettingsStore? = nil) {
        self.world = world
        if let settings {
            automaticBlinkingEnabled = settings.bool(.characterBlinking)
            dialogueExpressionsEnabled = settings.bool(.characterDialogueExpressions)
            eyeMovementEnabled = settings.bool(.characterEyeMovement)
        }
    }

    private var selectedPlayback: FaceMorphPlayback? {
        guard let world, let actor = world.faceMorphSubject else { return nil }
        return world.faceMorphPlayback(for: actor)
    }

    /// Shows `emotion` on `actor`'s face. With `seconds`, it ends on its own. The face
    /// moves to it at the speaking emotion change speed.
    public func showEmotion(
        _ emotion: TopicInfo.Response.Emotion, value: UInt32, on actor: FormID,
        now: Float, seconds: Float? = nil
    ) {
        emotions[actor] = HeldEmotion(
            emotion: emotion,
            weights: FacialExpressionCore.emotionWeights(emotion, value: value),
            until: seconds.map { now + max($0, 0) }
        )
        let rate = settings.speakingEmotionRate(rolls: (random(), random()))
        faces[actor, default: FaceState(nextBlink: now + blinkDelay())].rate = rate
    }

    public func clearEmotion(on actor: FormID) {
        emotions[actor] = nil
    }

    /// Sets every loaded face's automatic weights for animation time `now`.
    public func tick(now: Float) {
        let elapsed = lastTick.map { max(now - $0, 0) } ?? 0
        lastTick = now
        emotions = emotions.filter { $0.value.until.map { $0 > now } ?? true }
        var next: [FormID: FaceState] = [:]
        for playback in world?.faceMorphPlaybacks ?? [] {
            let actor = playback.actor
            var face = faces[actor] ?? FaceState(nextBlink: now + blinkDelay())
            let held = emotions[actor]
            let goal = dialogueExpressionsEnabled ? held?.weights ?? [:] : [:]
            let step = face.rate.isFinite ? face.rate * elapsed : .infinity
            face.shown = FacialExpressionCore.ease(face.shown, toward: goal, step: step)
            let eyes = eyeMovementEnabled ? FacialExpressionCore.eyeWeights(
                eyeOffset(of: actor, held: held, now: now), settings: settings
            ) : [:]
            let blink = automaticBlinkingEnabled ? blinkClosure(of: &face, now: now) : 0
            playback.setExpressionWeights(
                FacialExpressionCore.weights(emotion: face.shown, eyes: eyes, blink: blink)
            )
            next[actor] = face
        }
        faces = next
    }

    private func blinkDelay() -> Float {
        HeadTrackingCore.lerp(settings.blinkDelayMin, settings.blinkDelayMax, random())
    }

    private func blinkClosure(of face: inout FaceState, now: Float) -> Float {
        if face.blinkStart == nil, now >= face.nextBlink {
            face.blinkStart = now
        }
        guard let start = face.blinkStart else { return 0 }
        let elapsed = now - start
        if elapsed >= settings.blinkDownTime + settings.blinkUpTime {
            face.blinkStart = nil
            face.nextBlink = now + blinkDelay()
            return 0
        }
        return FacialExpressionCore.blinkClosure(elapsed: elapsed, settings: settings)
    }

    private func eyeOffset(of actor: FormID, held: HeldEmotion?, now: Float) -> HeadLook {
        let interval = settings.eyePickNewOffset
        let spread = Float(actor.rawValue % 1000) / 1000 * max(interval, 0)
        return FacialExpressionCore.eyeOffset(
            at: now + spread, seed: actor.rawValue,
            range: settings.eyeRange(for: held?.emotion), interval: interval
        )
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
