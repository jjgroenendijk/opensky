// Scripts on one form act as one object, so a cast between them finds the sibling.

import Foundation
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import OpenSkyScriptingInterface
import Testing

@MainActor
struct PapyrusWorldSiblingTests {
    /// The game keeps all scripts of one quest in one object, so a fragment can cast
    /// itself to the quest script.
    @Test func aFragmentFindsItsQuestScriptAsASibling() throws {
        let session = try PapyrusQuestFixture.session(quest: PapyrusQuestFixture.quest())
        let world = session.world
        let quest = world.instancesByKey[
            PapyrusQuestFixture.instanceKey(PapyrusQuestFixture.questScript)
        ]
        let fragment = try #require(world.instancesByKey[
            PapyrusQuestFixture.instanceKey(PapyrusQuestFixture.fragmentScript)
        ])
        #expect(world.sibling(of: fragment, as: PapyrusQuestFixture.questScript) == quest)
        #expect(world.sibling(of: fragment, as: "NoSuchScript") == nil)
    }
}
