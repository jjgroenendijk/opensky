import OpenSkyGameData
import Testing

struct MenuTextNamesTests {
    @Test func theRiddenDragonRefusalIsAMenuText() {
        #expect(MenuRecordData.isMenuText("sTESVDLC2DragonUnableToFlyMessage"))
        #expect(MenuRecordData.isMenuText("sNoFastTravelCombat"))
        #expect(!MenuRecordData.isMenuText("sMissingName"))
    }
}
