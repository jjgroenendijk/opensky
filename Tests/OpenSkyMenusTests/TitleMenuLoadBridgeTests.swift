// The main menu movie's Load list over a synthetic runtime: characters newest
// first, one character's saves with the measured fields, and the save picture.

import FormatsTesting
import Foundation
import OpenSkyFormatsSWF
@testable import OpenSkyMenus
import Testing

@MainActor
private final class CallLog {
    var calls: [TitleMenuLoadBridge.Call] = []
}

@MainActor
struct TitleMenuLoadBridgeTests {
    private static let rows = [
        SaveSlotRow(
            slot: "Save 1", title: "Save 1 - Ada", detail: "",
            savedAt: Date(timeIntervalSince1970: 10),
            character: SaveSlotCharacter(name: "Ada", race: "Nord", level: 3, playTime: "0:10")
        ),
        SaveSlotRow(
            slot: "Save 2", title: "Save 2 - Bo", detail: "",
            savedAt: Date(timeIntervalSince1970: 30),
            character: SaveSlotCharacter(name: "Bo", race: "Breton", level: 1, playTime: "0:05")
        ),
        SaveSlotRow(
            slot: "Save 3", title: "Save 3 - Ada", detail: "",
            savedAt: Date(timeIntervalSince1970: 20),
            character: SaveSlotCharacter(name: "Ada", race: "Nord", level: 4, playTime: "0:20")
        )
    ]

    @Test func charactersComeNewestFirstWithTheirSaves() {
        #expect(TitleMenuLoadBridge.characters(Self.rows) == ["Bo", "Ada"])
        #expect(TitleMenuLoadBridge.saves(of: "Ada", in: Self.rows).map(\.slot) == [
            "Save 3",
            "Save 1"
        ])
    }

    @Test func theListsFillAndTheMovieHearsTheyAreDone() throws {
        let runtime = try SWFRuntimeFixture.started(tags: [SWFDisplayFixture.showFrameTag])
        var calls: [String] = []
        for name in ["onFillCharacterListComplete", "onSaveLoadBatchComplete"] {
            AS2Natives.method(runtime.runtime, on: runtime.root.object, name: name) { context in
                calls.append("\(name)(\(context.arguments.count))")
                return .undefined
            }
        }
        let log = CallLog()
        TitleMenuLoadBridge.prepare(runtime: runtime) { log.calls.append($0) }
        let characters = runtime.runtime.makeArray()
        runtime.callHost("PopulateCharacterList", arguments: [.object(characters), .integer(20)])
        TitleMenuLoadBridge.fillCharacters(["Bo", "Ada"], runtime: runtime)
        #expect(characters.arrayLength == 2)
        #expect(characters.element(at: 1).objectValue?.lookup("text")?.property
            .value == .string("Ada"))

        let saves = runtime.runtime.makeArray()
        runtime.callHost(
            "CharacterSelected",
            arguments: [.integer(1), .integer(0), .boolean(false), .object(saves), .integer(20)]
        )
        #expect(log.calls.last == .init(request: .characterSelected, index: 1))
        TitleMenuLoadBridge.fillSaves(
            TitleMenuLoadBridge.saves(of: "Ada", in: Self.rows),
            runtime: runtime
        )
        let first = try #require(saves.element(at: 0).objectValue)
        #expect(first.lookup("level")?.property.value == .integer(4))
        #expect(first.lookup("raceName")?.property.value == .string("Nord"))
        #expect(first.lookup("corrupt")?.property.value == .boolean(false))
        #expect(calls == ["onFillCharacterListComplete(1)", "onSaveLoadBatchComplete(3)"])
    }

    @Test func thePictureScalesToTheSlotAndFallsBackToGrey() {
        let red = SaveSlotPicture(width: 2, height: 1, rgba: Data([255, 0, 0, 255, 0, 0, 255, 255]))
        let scaled = [UInt8](TitleMenuLoadBridge.screenshotPixels(red))
        let width = TitleMenuLoadBridge.screenshotWidth
        #expect(scaled.count == width * TitleMenuLoadBridge.screenshotHeight * 4)
        #expect(Array(scaled[0 ..< 4]) == [255, 0, 0, 255])
        #expect(Array(scaled[(width - 1) * 4 ..< width * 4]) == [0, 0, 255, 255])
        #expect(Array(TitleMenuLoadBridge.screenshotPixels(nil).prefix(4)) == [
            0x80,
            0x80,
            0x80,
            0xFF
        ])
    }
}
