// ShoutStore link resolution and the shout-family text dump.
// Synthetic plugins only; nothing here reads the game install.

import Foundation
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import Testing

struct ShoutStoreTests {
    @Test
    func theStoreJoinsEachShoutWordAgainstItsWordAndSpell() throws {
        let store = try ShoutStore(plugins: [("Base.esm", ShoutPluginFixture.plugin())])

        #expect(store.shouts.count == 1)
        #expect(store.words.count == 2)
        let shout = try #require(store.shout(editorID: "FireBreath"))
        #expect(shout.displayName == "Fire Breath")
        #expect(shout.words.count == 3)
        #expect(shout.words[0].word?.editorID == "FireBreathWord1")
        #expect(shout.words[0].wordName == "Y3")
        #expect(shout.words[0].spell?.editorID == "FireBreathSpell1")
        #expect(shout.words[0].spellName == "Fire Breath I")
        #expect(shout.words[1].wordName == "Toor")
        // The third entry is the all-zero placeholder a shorter shout stores.
        #expect(shout.words[2].wordName == "NULL")
        #expect(shout.words[2].spellName == "NULL")
    }

    // A word or spell link that names nothing in the load order stays visible
    // as its raw FormID rather than disappearing from the join.

    @Test
    func adanglingWordLinkRemainsVisible() throws {
        let store = try ShoutStore(plugins: [(
            "Base.esm",
            ShoutPluginFixture.plugin(danglingWord: true)
        )])
        let shout = try #require(store.shout(editorID: "FireBreath"))

        #expect(shout.words[0].word == nil)
        #expect(shout.words[0].wordName.hasPrefix("[UNRESOLVED]"))
    }
}
