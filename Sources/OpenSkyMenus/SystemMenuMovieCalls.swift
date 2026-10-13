// The System page of `quest_journal.swf` runs its own Save, Load, Controls, and Quit
// pages. It asks the engine for each list and each file action through
// `GameDelegate`; this names those calls and fills the lists it hands over.

import Foundation
import OpenSkyFormatsSWF

nonisolated extension SystemMenuMovieBridge {
    public static let saveLoadListPath = "\(systemPagePath)/SaveLoadPanel/List_mc"
    /// `MappingList` is the `InputMappingPanel` clip itself.
    public static let mappingListPath = "\(systemPagePath)/InputMappingPanel"

    /// The `SystemPage` state the movie shows, such as 1 for the save list.
    public static func pageState(runtime: SWFMovieRuntime) -> Int? {
        guard
            let page = runtime.node(atPath: systemPagePath, from: runtime.root),
            case let .number(state) = page.object.lookup("iCurrentState")?.property.value
        else { return nil }
        return Int(state)
    }

    /// Movie-to-engine calls of the System page.
    public enum Request: String, CaseIterable, Sendable {
        case quicksave = "QuickSave"
        /// `SAVE([entryList, batchSize])`: the saves to write over.
        case saveList = "SAVE"
        case loadList = "LOAD"
        case characters = "PopulateCharacterList"
        case characterSelected = "CharacterSelected"
        case screenshot = "PrepSaveGameScreenshot"
        case confirmLoad = "IsOKtoLoad"
        /// The list row; row 0 is the New Save row.
        case saveGame = "SaveGame"
        case loadGame = "LoadGame"
        /// The file's index, without the New Save row.
        case deleteSave = "DeleteSave"
        case inputMappings = "RequestInputMappings"
        /// `StartRemapMode([actionName, entryList])`.
        case startRemap = "StartRemapMode"
        case resetControls = "ResetControlsToDefaults"
        case quitToMainMenu = "QuitToMainMenu"
        case quitToDesktop = "QuitToDesktop"
    }

    /// Calls that need no answer: the list fills at once, and settings save as they change.
    public static let quietRequests = [
        "UseCurrentCharacterFilter", "ForceStopSaveListLoading", "SaveControls", "SaveSettings",
        "SetSaveDisabled"
    ]

    public struct Call: Equatable, Sendable {
        public let request: Request
        /// The first non-negative number the call passed.
        public let index: Int?
        /// The first string the call passed.
        public let text: String?
    }

    /// Queues each call; the coordinator answers it after the event that made it.
    public static func registerCalls(
        runtime: SWFMovieRuntime,
        onCall: @escaping @MainActor @Sendable (Call) -> Void
    ) {
        for request in Request.allCases {
            runtime.registerHostFunction(request.rawValue) { call in
                let made = Call(
                    request: request, index: TitleMenuLoadBridge.index(call.arguments),
                    text: call.arguments.lazy.compactMap(Self.string).first
                )
                MainActor.assumeIsolated { onCall(made) }
                return .undefined
            }
        }
        for name in quietRequests {
            runtime.registerHostFunction(name) { _ in .undefined }
        }
    }

    private static func string(_ value: AS2Value) -> String? {
        if case let .string(text) = value {
            text
        } else {
            nil
        }
    }

    // MARK: - Answers

    /// Fills the list a `SAVE` or `LOAD` call passed.
    public static func fillSaveList(
        _ rows: [SaveSlotRow], request: Request, runtime: SWFMovieRuntime
    ) {
        let list = runtime.lastHostArguments[request.rawValue]?.first
        TitleMenuLoadBridge.fillSaves(
            rows, list: list, listPath: saveLoadListPath, runtime: runtime
        )
    }

    /// One row per remappable gameplay action. `buttonName` is the symbol of the
    /// key's button art, and `buttonID` its hex fallback.
    public static func mappingRows(
        _ bindings: InputBindings, keyName: (UInt32) -> String
    ) -> [[String: AS2Value]] {
        InputBindings.slots.enumerated().compactMap { index, slot in
            guard
                slot.context == .gameplay, slot.remappable,
                !bindings.fixedKeys.contains(slot.key)
            else { return nil }
            let code = bindings.scanCode(for: slot.action)
            return [
                "text": .string(slot.event), "sortIndex": .integer(index),
                "buttonName": .string(code.map(keyName) ?? ""),
                "buttonID": code.map { .integer(Int($0)) } ?? .undefined
            ]
        }
    }

    /// Replaces the rows of the Controls list the movie passed with `request`.
    public static func fillMappings(
        _ rows: [[String: AS2Value]], request: Request, runtime: SWFMovieRuntime
    ) {
        let arguments = runtime.lastHostArguments[request.rawValue] ?? []
        let list = arguments.first { $0.objectValue != nil }
        TitleMenuLoadBridge.fill(rows, list: list, runtime: runtime)
    }

    /// Ends the movie's wait for a key; false shows "That button is reserved."
    public static func finishRemap(succeeded: Bool, runtime: SWFMovieRuntime) {
        runtime.callMovie("FinishRemapMode", arguments: [.boolean(succeeded)])
    }
}
