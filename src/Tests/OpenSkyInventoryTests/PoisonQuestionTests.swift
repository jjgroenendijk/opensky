import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import Testing

struct PoisonQuestionTests {
    @Test func aBowNamesThePoisonAndABladeNamesItself() {
        #expect(PoisonQuestion.text(
            isRanged: false, weapon: "Iron Dagger", poison: "Weak Poison", texts: .vanilla
        ) == "Do you want to poison the Iron Dagger?")
        #expect(PoisonQuestion.text(
            isRanged: true, weapon: "Hunting Bow", poison: "Weak Poison", texts: .vanilla
        ) == "Do you want to poison your next shot with the Weak Poison?")
    }
}
