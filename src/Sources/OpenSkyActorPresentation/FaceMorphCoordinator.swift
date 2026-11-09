// The Face Morphs readout, and the automatic face of every loaded actor: blinking, eye
// drift, and the emotion of the line a speaker says. See docs/engine/face-morphs.md.

import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyWorldInterface

/// What `FaceMorphCoordinator` reads from the running world.
public protocol FaceMorphWorld: AnyObject {
    /// The speaker, else the actor the Talk prompt targets.
    var faceMorphSubject: FormID? { get }
    func faceMorphPlayback(for actor: FormID) -> FaceMorphPlayback?
    /// Every loaded face, for blinking.
    var faceMorphPlaybacks: [FaceMorphPlayback] { get }
    /// The fear, combat, and mood state the face of `actor` shows.
    func faceMood(of actor: FormID) -> FaceMoodInput
}

extension FaceMorphWorld {
    public func faceMood(of _: FormID) -> FaceMoodInput {
        .calm
    }
}

public final class FaceMorphCoordinator {
    /// An emotion on one face, until an animation time, or until cleared.
    private struct HeldEmotion {
        let emotion: TopicInfo.ResponseEmotion
        let value: UInt32
        let until: Float?
    }

    /// One face's automatic state between frames.
    private struct FaceState {
        var nextBlink: Float
        var blinkStart: Float?
        /// The expression weights on screen, easing toward the goal.
        var shown: [String: Float] = [:]
    }

    weak let world: (any FaceMorphWorld)?
    public let settings: FaceAnimationSettings
    public var automaticBlinkingEnabled = true
    public var dialogueExpressionsEnabled = true
    public var eyeMovementEnabled = true
    /// A number in 0 ..< 1 for blink gaps. A test fixes it.
    public var random: () -> Float = { [stream = RandomStream(seed: 0x4641_4345)] in
        stream.float(in: 0 ..< 1)
    }

    private var emotions: [FormID: HeldEmotion] = [:]
    private var faces: [FormID: FaceState] = [:]
    private var lastTick: Float?

    /// `settings` gives the persisted blinking, expression, and eye switches.
    public init(
        world: (any FaceMorphWorld)? = nil,
        settings: PlayerSettingsStore? = nil,
        animation: FaceAnimationSettings = .vanilla
    ) {
        self.settings = animation
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

    /// Shows `emotion` on `actor`'s face while it speaks. With `seconds`, it ends on its
    /// own.
    public func showEmotion(
        _ emotion: TopicInfo.ResponseEmotion, value: UInt32, on actor: FormID,
        now: Float, seconds: Float? = nil
    ) {
        emotions[actor] = HeldEmotion(
            emotion: emotion, value: value, until: seconds.map { now + max($0, 0) }
        )
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
            let goal = dialogueExpressionsEnabled ? FacialMoodRules.goal(
                world?.faceMood(of: actor) ?? .calm,
                speaking: held.map { ($0.emotion, $0.value) }
            ) : [:]
            let step = FacialMoodRules.rate(toward: goal) * elapsed
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
            pairedPaths: playback.pairedPaths,
            associationMisses: playback.misses.map { "\($0.headPart): \($0.reason)" },
            unknownTargetCount: playback.unknownTargetCount
        )
    }

    public func setFaceMorphWeight(_ weight: Float, target: String) {
        selectedPlayback?.setWeight(weight, for: target)
    }
}
