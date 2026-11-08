// The beast form rules: which form the flag and the race give, and which activations a
// beast or a race without "Can Pick Up Items" is refused.

@testable import OpenSkyPlayer
import OpenSkyWorldInterface
import Testing

struct PlayerBeastFormTests {
    @Test func theRaceDecidesTheFormAndTheFlagMarksAnOtherBeast() {
        #expect(PlayerBeastForm.resolve(beastFormFlag: true, raceEditorID: "WerewolfBeastRace")
            == .werewolf)
        #expect(PlayerBeastForm.resolve(beastFormFlag: false, raceEditorID: "DLC1VampireBeastRace")
            == .vampireLord)
        #expect(PlayerBeastForm.resolve(beastFormFlag: true, raceEditorID: "NordRace")
            == .otherBeast)
        #expect(PlayerBeastForm.resolve(beastFormFlag: false, raceEditorID: "NordRace") == .none)
    }

    @Test func aBeastCannotTalkAndARaceWithoutPickupCannotTake() {
        #expect(PlayerBeastForm.werewolf.refusal(for: .talk, raceCanPickUpItems: false)
            == .beastForm)
        #expect(PlayerBeastForm.werewolf.refusal(for: .take, raceCanPickUpItems: false)
            == .beastForm)
        #expect(PlayerBeastForm.werewolf.refusal(for: .search, raceCanPickUpItems: false) == nil)
        #expect(PlayerBeastForm.werewolf.refusal(for: .activate, raceCanPickUpItems: false) == nil)
        #expect(PlayerBeastForm.none.refusal(for: .talk, raceCanPickUpItems: true) == nil)
        #expect(PlayerBeastForm.none.refusal(for: .take, raceCanPickUpItems: true) == nil)
    }
}
