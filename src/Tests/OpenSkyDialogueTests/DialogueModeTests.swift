// The dialogue mode countdown: how a start, a line, and the frame time change it.

import OpenSkyDialogueInterface
import OpenSkyFormatsESM
import Testing

struct DialogueModeTests {
    private static let actor = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x10)
    private static let other = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x11)

    @Test func aStartAddsTheTimeForTheActorAndThePlayer() {
        var mode = DialogueModeState()
        mode.dialogueStarted(with: Self.actor, time: 60)
        mode.dialogueStarted(with: Self.actor, time: 60)
        #expect(mode.countdown(of: Self.actor) == 120)
        #expect(mode.playerCountdown == 120)
        mode.dialogueEnded()
        #expect(mode.playerCountdown == 0)
        #expect(mode.isTalking(Self.actor))
    }

    @Test func aLineSetsTheFullTimeAboveOneSecondAndAddsBelow() {
        var mode = DialogueModeState()
        mode.lineStarted(by: Self.actor, time: 60)
        #expect(mode.countdown(of: Self.actor) == 60)
        _ = mode.advance(by: 10)
        mode.lineStarted(by: Self.actor, time: 60)
        #expect(mode.countdown(of: Self.actor) == 60)
        _ = mode.advance(by: 59.5)
        mode.lineStarted(by: Self.actor, time: 60)
        #expect(mode.countdown(of: Self.actor) == 60.5)
    }

    @Test func theCountdownEndsDialogueModeAndASpeakerKeepsItsTime() {
        var mode = DialogueModeState()
        mode.lineStarted(by: Self.actor, time: 5)
        mode.lineStarted(by: Self.other, time: 5)
        #expect(mode.advance(by: 5, speaking: Self.other) == [Self.actor])
        #expect(!mode.isTalking(Self.actor))
        #expect(mode.talkingActors == [Self.other])
        mode.dialogueFailed(with: Self.other)
        #expect(mode.countdowns.isEmpty)
        #expect(mode.advance(by: 1).isEmpty)
    }
}
