// Clip annotation text to engine action. The editor IDs are invented; the event
// shapes are the ones the census of the install's clips found.

import Foundation
@testable import OpenSkyBehavior
import Testing

struct AnimationEventActionTests {
    @Test func soundEventsNameTheirDescriptor() {
        #expect(AnimationEventAction.parse("SoundPlay.TestClap")
            == .playSound(editorID: "TestClap", node: nil))
        #expect(AnimationEventAction.parse("soundPlay.TestClap")
            == .playSound(editorID: "TestClap", node: nil))
        #expect(AnimationEventAction.parse("SoundPlayAt.TestSaw.Node01")
            == .playSound(editorID: "TestSaw", node: "Node01"))
    }

    /// A door mesh's sequence text key names its sound after `Sound:`.
    @Test func aSequenceTextKeyPlaysItsSound() {
        #expect(AnimationEventAction.parse("Sound: TestGateOpen")
            == .playSound(editorID: "TestGateOpen", node: nil))
        #expect(AnimationEventAction.parse("sound:TestGateOpen")
            == .playSound(editorID: "TestGateOpen", node: nil))
        #expect(AnimationEventAction.parse("Sound: ") == nil)
    }

    @Test func stopAndReleaseEndTheLoop() {
        #expect(AnimationEventAction.parse("SoundStop.TestLoopLPM")
            == .stopSound(editorID: "TestLoopLPM"))
        #expect(AnimationEventAction.parse("SoundStop.TestLoopLPM.Node01")
            == .stopSound(editorID: "TestLoopLPM"))
        #expect(AnimationEventAction.parse("SoundRelease.TestBark")
            == .stopSound(editorID: "TestBark"))
    }

    @Test func cameraShakeReadsItsStrength() {
        #expect(AnimationEventAction.parse("CameraShake.0.3") == .cameraShake(strength: 0.3))
        #expect(AnimationEventAction.parse("CameraShake.2") == .cameraShake(strength: 1))
        #expect(AnimationEventAction.parse("CameraShake.x") == nil)
        #expect(AnimationEventAction.parse("CameraShake.0") == nil)
    }

    @Test func headTrackingTogglesWithoutPayload() {
        #expect(AnimationEventAction.parse("HeadTrackingOn") == .headTracking(enabled: true))
        #expect(AnimationEventAction.parse("HeadTrackingOff") == .headTracking(enabled: false))
    }

    /// The graph and the other runtimes own these, so the parser leaves them alone.
    @Test func otherEventsAskForNothing() {
        let others = [
            "FootLeft", "HitFrame", "SoundPlay.", "SoundPlay", "2_SoundPlay.TestKill",
            "NPCSoundPlay.TestKill"
        ]
        for text in others {
            #expect(AnimationEventAction.parse(text) == nil, "\(text)")
        }
    }

    /// The gap report folds a payload to `.*`, so each listed name must parse once a
    /// payload stands in for the star.
    @Test func everyHandledEventParses() {
        for event in AnimationEventAction.handledEvents {
            let text = event.replacingOccurrences(of: ".*", with: ".0.5")
            #expect(AnimationEventAction.parse(text) != nil, "\(event)")
        }
    }
}
