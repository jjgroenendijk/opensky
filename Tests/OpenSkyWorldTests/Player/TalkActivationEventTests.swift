// The talk event a use-key press raises, for a picked actor and for a TACT.

@testable import OpenSkyFormatsESM
@testable import OpenSkyWorldInterface
import Testing

struct TalkActivationEventTests {
    private static func interaction(_ action: InteractionAction) -> PlacedInteraction {
        PlacedInteraction(
            reference: FormID(0x500),
            base: FormID(0x300),
            position: .zero,
            name: "Talking Skull",
            action: action,
            actionLabel: action.defaultLabel,
            sounds: nil,
            voiceType: FormID(0x0001_3AD5)
        )
    }

    private static func key(_ objectID: UInt32) -> ReferenceKey {
        ReferenceKey(resolved: ResolvedFormID(plugin: "Skyrim.esm", objectID: objectID))
    }

    @Test func talkingActivatorRaisesTalkWithItsVoiceType() {
        let event = TalkActivationEvent(
            interaction: Self.interaction(.talk),
            pickedSpeaker: nil,
            placedKey: { Self.key(0x500) }
        )
        #expect(event?.speaker == Self.key(0x500))
        #expect(event?.voiceType == FormID(0x0001_3AD5))
    }

    @Test func pickedActorNamesItselfWithoutAVoiceType() {
        let event = TalkActivationEvent(
            interaction: Self.interaction(.talk),
            pickedSpeaker: Self.key(0x700),
            placedKey: { Self.key(0x500) }
        )
        #expect(event?.speaker == Self.key(0x700))
        #expect(event?.voiceType == nil)
    }

    @Test func otherActionsRaiseNoTalk() {
        let event = TalkActivationEvent(
            interaction: Self.interaction(.harvest),
            pickedSpeaker: Self.key(0x700),
            placedKey: { Self.key(0x500) }
        )
        #expect(event == nil)
    }
}
