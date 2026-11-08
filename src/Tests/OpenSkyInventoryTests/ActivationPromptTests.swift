// The crosshair verb from the game's verb settings: theft, books, beds, seats, and a
// sneaking player at an actor.

@testable import OpenSkyFormatsESM
import OpenSkyGameData
@testable import OpenSkyInventory
@testable import OpenSkyWorldInterface
import Testing

struct ActivationPromptTests {
    private func interaction(_ action: InteractionAction) -> PlacedInteraction {
        PlacedInteraction(
            reference: FormID(0x10), base: FormID(0x20), position: .zero,
            name: "Thing", action: action, actionLabel: action.defaultLabel, sounds: nil
        )
    }

    @Test func aTheftShowsTheStealVerbs() {
        let theft = ActivationPromptContext(isTheft: true)
        #expect(ActivationPrompt.text(for: interaction(.take), context: theft) == .steal)
        #expect(ActivationPrompt.text(for: interaction(.search), context: theft) == .stealFrom)
        #expect(ActivationPrompt.text(for: interaction(.search), context: .init()) == .search)
    }

    @Test func aBookReadsAndASneakingPlayerPickpockets() {
        #expect(
            ActivationPrompt.text(for: interaction(.take), context: .init(isBook: true)) == .read
        )
        let sneaking = ActivationPromptContext(isPlayerSneaking: true)
        #expect(ActivationPrompt.text(for: interaction(.talk), context: sneaking) == .pickpocket)
        #expect(ActivationPrompt.text(for: interaction(.talk), context: .init()) == .talk)
    }

    @Test func furnitureSitsOrSleepsAndAnAuthoredVerbStays() {
        var bed = interaction(.use)
        bed.seats = [
            FurnitureSeat(position: .zero, heading: 0, animationType: 2, keyword: nil)
        ]
        #expect(ActivationPrompt.text(for: bed, context: .init()) == .sleep)
        var chair = interaction(.use)
        chair.seats = [
            FurnitureSeat(position: .zero, heading: 0, animationType: 1, keyword: nil)
        ]
        #expect(ActivationPrompt.text(for: chair, context: .init()) == .sit)
        #expect(ActivationPrompt.text(for: interaction(.use), context: .init()) == .activate)
        var authored = interaction(.activate)
        authored.hasLabelOverride = true
        #expect(ActivationPrompt.text(for: authored, context: .init()) == nil)
        let relabelled = ActivationPrompt.labelled(
            interaction(.take), context: .init(), texts: .vanilla
        )
        #expect(relabelled.actionLabel == "Take")
    }
}
