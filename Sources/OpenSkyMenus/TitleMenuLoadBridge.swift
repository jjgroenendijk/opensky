// The Load list of `Interface\startmenu.swf`: the characters, then one character's
// saves with their pictures, then a confirmed load. The calls were measured with the
// action disassembler; docs/engine/main-menu.md lists them.

import Foundation
import OpenSkyFormatsSWF

nonisolated public enum TitleMenuLoadBridge: Sendable {
    /// The `img://` name the save list loads its picture from.
    public static let screenshotSlot = "BGSSaveLoadHeader_Screenshot"
    public static let screenshotWidth = 192
    public static let screenshotHeight = 108
    static let unknownCharacter = "Unknown"

    /// Movie-to-engine calls of the Load list.
    public enum Request: String, CaseIterable, Sendable {
        case characters = "PopulateCharacterList"
        case characterSelected = "CharacterSelected"
        case screenshot = "PrepSaveGameScreenshot"
        case confirmLoad = "IsOKtoLoad"
        case load = "LoadGame"
        case back = "OnSaveLoadPanelBackClicked"
        case stopLoading = "ForceStopSaveListLoading"
        case delete = "DeleteSave"
    }

    /// One call, answered after the movie event that made it. A list the call passed
    /// stays in the runtime's `lastHostArguments`.
    public struct Call: Equatable, Sendable {
        public let request: Request
        /// The list index the call names: its first number.
        public let index: Int?

        public init(request: Request, index: Int?) {
            self.request = request
            self.index = index
        }

        public init(request: Request, arguments: [AS2Value]) {
            self.init(request: request, index: TitleMenuLoadBridge.index(arguments))
        }
    }

    public static func prepare(
        runtime: SWFMovieRuntime,
        onCall: @escaping @MainActor @Sendable (Call) -> Void
    ) {
        for request in Request.allCases {
            runtime.registerHostFunction(request.rawValue) { call in
                let made = Call(request: request, arguments: call.arguments)
                MainActor.assumeIsolated { onCall(made) }
                return .undefined
            }
        }
    }

    // MARK: - Rows

    /// Character names, the one with the newest save first.
    public static func characters(_ rows: [SaveSlotRow]) -> [String] {
        var newest: [String: Date] = [:]
        for row in rows {
            let name = row.character?.name ?? unknownCharacter
            newest[name] = max(newest[name] ?? .distantPast, row.savedAt)
        }
        return newest.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map(\.key)
    }

    public static func saves(of character: String, in rows: [SaveSlotRow]) -> [SaveSlotRow] {
        SaveLoadPageModel
            .sorted(rows.filter { ($0.character?.name ?? unknownCharacter) == character })
    }

    static func index(_ arguments: [AS2Value]) -> Int? {
        for argument in arguments {
            if case let .number(value) = argument, value.isFinite, value >= 0 {
                return Int(value)
            }
        }
        return nil
    }

    // MARK: - Answers

    /// `PopulateCharacterList([entryList, batchSize])`.
    public static func fillCharacters(_ names: [String], runtime: SWFMovieRuntime) {
        let arguments = runtime.lastHostArguments[Request.characters.rawValue] ?? []
        let rows = names.enumerated().map { index, name -> [String: AS2Value] in
            ["text": .string(name), "id": .integer(index), "flags": .integer(0)]
        }
        fill(rows, list: arguments.first, runtime: runtime)
        runtime.callMovie("onFillCharacterListComplete", arguments: [.boolean(true)])
        selectFirstRow(count: rows.count, runtime: runtime)
    }

    /// `CharacterSelected([id, flags, isSaving, entryList, batchSize])`.
    public static func fillSaves(_ saves: [SaveSlotRow], runtime: SWFMovieRuntime) {
        let arguments = runtime.lastHostArguments[Request.characterSelected.rawValue] ?? []
        let list = arguments.count > 3 ? arguments[3] : nil
        let entries = saves.enumerated().map { entry(index: $0.offset, row: $0.element) }
        fill(entries, list: list, runtime: runtime)
        let count = AS2Value.integer(saves.count)
        runtime.callMovie("onSaveLoadBatchComplete", arguments: [.boolean(true), count, count])
        selectFirstRow(count: saves.count, runtime: runtime)
    }

    /// The filled list starts with no row selected, and a key does not move it
    /// from there, so the first row is picked as the game shows it.
    private static func selectFirstRow(count: Int, runtime: SWFMovieRuntime) {
        guard count > 0 else { return }
        runtime.callMovie(
            "__set__selectedIndex", atPath: TitleMenuMovieBridge.saveLoadListPath,
            arguments: [.integer(0)]
        )
    }

    static func entry(index: Int, row: SaveSlotRow) -> [String: AS2Value] {
        let date = row.savedAt.formatted(date: .abbreviated, time: .shortened)
        return [
            "text": .string(row.title), "fileNum": .integer(index), "id": .integer(index),
            "name": .string(row.character?.name ?? ""),
            "raceName": .string(row.character?.race ?? ""),
            "level": .integer(row.character?.level ?? 0),
            "playTime": .string(row.character?.playTime ?? ""), "dateString": .string(date),
            "corrupt": .boolean(row.error != nil), "obsolete": .boolean(false), "flags": .integer(0)
        ]
    }

    private static func fill(
        _ rows: [[String: AS2Value]],
        list: AS2Value?,
        runtime: SWFMovieRuntime
    ) {
        guard let list = list?.objectValue else { return }
        list.markArray(length: 0)
        for (index, fields) in rows.enumerated() {
            let row = runtime.runtime.makeObject()
            for name in fields.keys.sorted() {
                row.assign(fields[name] ?? .undefined, for: name)
            }
            list.setElement(.object(row), at: index)
        }
    }

    /// The picture scaled to the slot by nearest pixel, or mid grey without one.
    public static func screenshotPixels(_ picture: SaveSlotPicture?) -> Data {
        let width = screenshotWidth, height = screenshotHeight
        guard
            let picture, picture.width > 0, picture.height > 0,
            picture.rgba.count == picture.width * picture.height * 4
        else {
            var grey = [UInt8](repeating: 0x80, count: width * height * 4)
            for alpha in stride(from: 3, to: grey.count, by: 4) {
                grey[alpha] = 0xFF
            }
            return Data(grey)
        }
        let source = [UInt8](picture.rgba)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0 ..< height {
            let sourceY = y * picture.height / height
            for x in 0 ..< width {
                let from = (sourceY * picture.width + x * picture.width / width) * 4
                let to = (y * width + x) * 4
                pixels[to ..< to + 4] = source[from ..< from + 4]
            }
        }
        return Data(pixels)
    }
}
