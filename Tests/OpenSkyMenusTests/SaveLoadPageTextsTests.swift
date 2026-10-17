// The save page's new-save row and its questions come from the save texts.

import Foundation
@testable import OpenSkyGameData
@testable import OpenSkyMenus
import Testing

struct SaveLoadPageTextsTests {
    @Test func theNewSaveRowAndTheQuestionsUseTheTexts() {
        var texts = SaveTexts.vanilla
        texts.newSave = "NEW"
        texts.overwriteQuestion = "Overwrite this game?"
        texts.deleteQuestion = "Delete %s now?"
        let row = SaveSlotRow(
            slot: "A", title: "A", detail: "", savedAt: Date(timeIntervalSince1970: 1)
        )
        var page = SaveLoadPageModel(mode: .save, rows: [row], texts: texts)
        #expect(page.titles.first == "NEW")
        page.handle(.move(.down))
        page.handle(.button(.accept))
        #expect(page.confirmation?.question == "Overwrite this game?")
        page.handle(.button(.cancel))
        page.requestDelete()
        #expect(page.confirmation?.question == "Delete A now?")
    }
}
