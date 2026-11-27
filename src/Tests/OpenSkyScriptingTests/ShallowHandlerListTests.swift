// ShallowHandlerList: the tool's rows parse, and the gap rows rank the shallow handlers the
// data uses, with the on-purpose ones counted as done.

import Foundation
@testable import OpenSkyScripting
import Testing

struct ShallowHandlerListTests {
    private static let text = """
    native\tGame.UsingGamepad\tshallow\t.returned(.boolean(false))
    native\t*.IsLockBroken\tshallow\t.returned(.boolean(false))
    native\tSound.Play\tworks\t
    native\tSound.Play\tshallow\t.returned(.integer(0))
    native\tDebug.DBSendPlayerPosition\ton-purpose\tno retail game reaches it
    native\tGame.Unused\tshallow\t.returned(.none)
    condition\tIsHorseStolen\ton-purpose\ta no-op in the game

    """

    @Test func ranksTheUsedShallowHandlers() throws {
        let list = try ShallowHandlerList(text: Self.text)
        let natives = list.gaps(.native, uses: [
            "Game.UsingGamepad": 4, "ObjectReference.IsLockBroken": 2, "Lock.IsLockBroken": 3,
            "sound.play": 9, "Debug.DBSendPlayerPosition": 1
        ])
        #expect(natives.done == 2)
        #expect(natives.left.map(\.name) == [
            "*.islockbroken answers .returned(.boolean(false))",
            "game.usinggamepad answers .returned(.boolean(false))"
        ])
        #expect(natives.left.map(\.count) == [5, 4])
        #expect(natives.onPurpose == ["debug.dbsendplayerposition: no retail game reaches it"])
        let conditions = list.gaps(.condition, uses: ["IsHorseStolen": 6])
        #expect(conditions.done == 1 && conditions.left.isEmpty)
        #expect(list.gaps(.native, uses: ["Game.UsingGamepad": 4]) != natives)
        #expect(list.gaps(.condition, uses: ["IsHorseStolen": 6]) == conditions)
    }

    @Test func rejectsAMalformedLine() {
        #expect(throws: ShallowHandlerList.ParseError.malformedLine(1)) {
            try ShallowHandlerList(text: "native\tGame.X\tmaybe\t\n")
        }
    }
}
