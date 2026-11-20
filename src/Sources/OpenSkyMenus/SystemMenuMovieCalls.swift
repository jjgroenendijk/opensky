// The System page of `quest_journal.swf` runs its own Save, Load, Controls, and Quit
// pages. It asks the engine for each list and each file action through
// `GameDelegate`; this names those calls and fills the lists it hands over.

import Foundation
public import OpenSkyFormatsSWF
import OpenSkyMenusInterface

nonisolated extension SystemMenuMovieBridge {
    static let saveLoadListPath = "\(systemPagePath)/SaveLoadPanel/List_mc"
    /// `MappingList`, the list clip inside `InputMappingPanel`. The panel has no
    /// `InvalidateData` of its own.
    static let mappingListPath = "\(systemPagePath)/InputMappingPanel/List_mc"
    /// The computer's Quit list: Main Menu and Desktop, with no Cancel row.
    static let quitListPath = "\(systemPagePath)/PCQuitPanel/List_mc"

    /// The `SystemPage` state the movie shows, such as 1 for the save list.
    static func pageState(runtime: SWFMovieRuntime) -> Int? {
        guard
            let page = runtime.node(atPath: systemPagePath, from: runtime.root),
            case let .number(state) = page.object.lookup("iCurrentState")?.property.value
        else { return nil }
        return Int(state)
    }

    /// Movie-to-engine calls of the System page.
    enum Request: String, CaseIterable, Sendable {
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
        /// The movie waits for `onSettingsSaved` after either call.
        case saveSettings = "SaveSettings"
        case saveControls = "SaveControls"
    }

    /// Calls that need no answer: the list fills at once.
    static let quietRequests = [
        "UseCurrentCharacterFilter", "ForceStopSaveListLoading", "SetSaveDisabled"
    ]

    /// Ends the movie's `$Saving...` wait, which holds its input.
    static func finishSaving(runtime: SWFMovieRuntime) {
        runtime.callMovie("onSettingsSaved", atPath: systemPagePath)
    }

    struct Call: Equatable, Sendable {
        let request: Request
        /// The first non-negative number the call passed.
        let index: Int?
        /// The first string the call passed.
        let text: String?
    }

    /// Queues each call; the coordinator answers it after the event that made it.
    /// `RequestInputMappings` is answered during the call instead, with `mappings`:
    /// in the same script the movie sorts the list it passed and draws it.
    static func registerCalls(
        runtime: SWFMovieRuntime,
        mappings: @escaping @MainActor @Sendable () -> [MappingEntry],
        onCall: @escaping @MainActor @Sendable (Call) -> Void
    ) {
        for request in Request.allCases {
            runtime.registerHostFunction(request.rawValue) { call in
                if request == .inputMappings {
                    let list = call.arguments.first { $0.objectValue != nil }
                    let rows = MainActor.assumeIsolated { mappings() }.map(\.fields)
                    TitleMenuLoadBridge.fill(rows, list: list, runtime: call.movie)
                    return .undefined
                }
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

    /// The CLI's way in: the Controls request gets the default bindings, and every
    /// other call is dropped.
    public static func registerDefaultCalls(runtime: SWFMovieRuntime) {
        registerCalls(
            runtime: runtime,
            mappings: { mappingEntries(InputBindings()) { "Key \($0)" } },
            onCall: { _ in }
        )
    }

    /// The Controls rows the movie draws.
    public static func shownMappingRows(runtime: SWFMovieRuntime) -> Int {
        InventoryMenuMovieBridge.shownClipCount(runtime: runtime, atPath: mappingListPath)
    }

    /// The rows a movie list draws and the one it highlights.
    static func listRows(atPath path: String, runtime: SWFMovieRuntime) -> SystemMenuPageSnapshot {
        SystemMenuPageSnapshot(
            rows: MenuMovieEntryList.labels(atPath: path, runtime: runtime),
            selectedIndex: InventoryMenuMovieBridge.selectedIndex(runtime: runtime, atPath: path)
                ?? 0
        )
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
    static func fillSaveList(
        _ rows: [SaveSlotRow], request: Request, runtime: SWFMovieRuntime
    ) {
        let list = runtime.lastHostArguments[request.rawValue]?.first
        TitleMenuLoadBridge.fillSaves(
            rows, list: list, listPath: saveLoadListPath, runtime: runtime
        )
    }

    /// One row per remappable gameplay action. `buttonName` is the symbol of the
    /// key's button art, and `buttonID` its hex fallback. With a gamepad the rows are
    /// the ones the file lets a gamepad remap, with their `360_` art.
    static func mappingRows(
        _ bindings: InputBindings, keyName: (UInt32) -> String, gamepad: Bool = false
    ) -> [[String: AS2Value]] {
        mappingEntries(bindings, keyName: keyName, gamepad: gamepad).map(\.fields)
    }

    /// One Controls row as plain values, so it can leave the main actor.
    struct MappingEntry: Sendable {
        let text: String
        let sortIndex: Int
        let buttonName: String
        let buttonID: UInt32?

        var fields: [String: AS2Value] {
            [
                "text": .string(text), "sortIndex": .integer(sortIndex),
                "buttonName": .string(buttonName),
                "buttonID": buttonID.map { .integer(Int($0)) } ?? .undefined
            ]
        }
    }

    static func mappingEntries(
        _ bindings: InputBindings, keyName: (UInt32) -> String, gamepad: Bool = false
    ) -> [MappingEntry] {
        if gamepad {
            return gamepadMappingRows(bindings)
        }
        return InputBindings.slots.enumerated().compactMap { index, slot in
            guard
                slot.context == .gameplay, slot.remappable,
                !bindings.fixedKeys.contains(slot.key)
            else { return nil }
            let code = bindings.scanCode(for: slot.action)
            return MappingEntry(
                text: slot.event, sortIndex: index, buttonName: code.map(keyName) ?? "",
                buttonID: code
            )
        }
    }

    private static func gamepadMappingRows(_ bindings: InputBindings) -> [MappingEntry] {
        InputBindings.slots.enumerated().compactMap { index, slot in
            guard slot.context == .gameplay, bindings.gamepadKeys.contains(slot.key) else {
                return nil
            }
            let code = bindings.gamepadCodes(for: slot.action).first
            let art = code.flatMap { GamepadButton(controlMapCode: $0)?.artName }
            return MappingEntry(
                text: slot.event, sortIndex: index, buttonName: art ?? "", buttonID: code
            )
        }
    }

    /// Replaces the rows of the Controls list the movie passed with `request`.
    static func fillMappings(
        _ rows: [[String: AS2Value]], request: Request, runtime: SWFMovieRuntime
    ) {
        let arguments = runtime.lastHostArguments[request.rawValue] ?? []
        let list = arguments.first { $0.objectValue != nil }
        TitleMenuLoadBridge.fill(rows, list: list, runtime: runtime)
    }

    /// Ends the movie's wait for a key; false shows "That button is reserved."
    static func finishRemap(succeeded: Bool, runtime: SWFMovieRuntime) {
        runtime.callMovie("FinishRemapMode", arguments: [.boolean(succeeded)])
    }
}
