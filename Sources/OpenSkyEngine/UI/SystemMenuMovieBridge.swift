// Vanilla presentation layer for the system menu (M8.5.1): the measured AS2
// contract of `Interface\quest_journal.swf`. Device-free and AppKit-free so it
// builds into the CLI target and can be unit-tested against synthetic AS2
// fixtures; it owns no renderer and no movie lifetime. The engine-side selector
// it presents is UI/SystemMenuModel.swift.
//
// `quest_journal.swf` was the worst faulter before issue #136 at 159
// `callDepthExceeded` faults. It now starts and drives with zero faults. Its
// `SystemPage` builds the actual in-game system categories and their Settings
// and Quit submenus; no game-derived data is embedded here.

import Foundation

nonisolated enum SystemMenuMovieBridge {
    static let moviePath = "interface\\quest_journal.swf"
    /// The `QuestJournalBase` instance. Page switching is a direct method on
    /// this clip; engine lifecycle calls are `GameDelegate` callbacks.
    static let menuPath = "/QuestJournalFader/Menu_mc"
    static let systemPagePath = "\(menuPath)/SystemFader/Page_mc"
    static let systemCategoryListPath = "\(systemPagePath)/CategoryList_mc/List_mc"
    static let settingsCategoryListPath = "\(systemPagePath)/SettingsPanel/List_mc"
    static let systemFaderPath = "\(menuPath)/SystemFader"
    static let questsFaderPath = "\(menuPath)/QuestsFader"
    static let statsFaderPath = "\(menuPath)/StatsFader"

    /// `PLATFORM_PC_KBMOUSE`, the value the movie's platform switch expects for
    /// keyboard and mouse.
    static let pcPlatform = 0.0

    /// Movie-to-engine calls that do not mutate OpenSky state yet. The boolean
    /// queries return false; the rest are notifications or requests whose data
    /// consumers are outside the system-page surface.
    static let sinkHostFunctions = [
        "myLog", "PlaySound", "PlayOKSound", "RememberCurrentTabIndex",
        "RequestPlayerInfo"
    ]
    static let falseHostFunctions = ["ShouldShowMod", "GetIsRemoteDevice"]

    /// Scaleform's UI-sound hook, which the movie reaches for as a plain
    /// `_global` function rather than through `GameDelegate`. OpenSky has no UI
    /// sound bank yet, so it is a no-op rather than a missing name.
    static let globalSinkFunctions = ["gfxProcessSound"]

    /// `PageArray` is `[Quests, Stats, System]`, measured from the live movie.
    static let systemTabIndex = 2

    // MARK: - Bring-up

    /// Installs the surface the movie reaches for *during* `start()`. Bring-up
    /// is the first thing that calls out to the host, so this must run before
    /// the runtime is started (`Renderer.startSWFRuntime(prepare:)`).
    static func prepare(runtime: SWFMovieRuntime) {
        for name in sinkHostFunctions {
            runtime.registerHostFunction(name) { _ in .undefined }
        }
        for name in falseHostFunctions {
            runtime.registerHostFunction(name) { _ in .boolean(false) }
        }
        let global = runtime.runtime.globalObject
        for name in globalSinkFunctions {
            AS2Natives.method(runtime.runtime, on: global, name: name) { _ in .undefined }
        }
    }

    /// Opens the journal movie directly on its System page. Runs after
    /// `start()` because `InitExtensions` and `ShowMenu` are installed by the
    /// placed `QuestJournalBase` instance.
    ///
    /// Nothing here throws. A movie that does not match the measured contract
    /// leaves entries in the missing-API tally, which the panel reports.
    static func activate(
        runtime: SWFMovieRuntime,
        onClose: @escaping @MainActor @Sendable () -> Void
    ) {
        runtime.registerHostFunction("CloseMenu") { _ in
            MainActor.assumeIsolated {
                onClose()
            }
            return .undefined
        }
        runtime.callMovie("SetPlatform", arguments: [.number(pcPlatform)])
        runtime.callMovie("InitExtensions")
        runtime.callMovie("ShowMenu")
        runtime.callMovie(
            "SwitchPageToFront",
            atPath: menuPath,
            arguments: [.integer(systemTabIndex), .boolean(true)]
        )
        showSystemPage(runtime: runtime)
    }

    /// Routes the toolkit-free engine menu event into the Flash key model.
    /// Pointer deltas have no absolute stage position, so they remain
    /// unsupported here and fall back to the engine selector.
    @discardableResult
    static func handle(_ event: MenuInputEvent, runtime: SWFMovieRuntime) -> Bool {
        if
            case .button(.accept) = event,
            openSelectedSystemPage(runtime: runtime)
        {
            return true
        }
        guard let key = key(for: event) else {
            return false
        }
        let down = runtime.handle(.keyDown(code: key.code, ascii: key.ascii))
        let up = runtime.handle(.keyUp(code: key.code))
        return down || up
    }

    // MARK: - Readout

    /// Faults and distinct unresolved names, for the verification readout.
    static func diagnostics(runtime: SWFMovieRuntime) -> (faults: Int, missingNames: Int) {
        let tally = runtime.tally
        return (tally.faultTotal, tally.missingNames.count)
    }

    /// The page brought to the front, derived from the actual System category
    /// rows rather than a bridge-owned flag.
    static func currentState(runtime: SWFMovieRuntime) -> String? {
        guard
            let fader = runtime.node(atPath: systemFaderPath, from: runtime.root),
            let index = fader.timeline?.frameIndex(forLabel: "forceFade"),
            fader.currentFrame == index
        else {
            return nil
        }
        return "System"
    }

    /// The row labels the movie actually built, read back from the list's own
    /// entry array. These prove that the expected movie loaded; `currentState`
    /// separately proves that activation brought the System page to the front.
    static func entryLabels(runtime: SWFMovieRuntime) -> [String] {
        entryLabels(runtime: runtime, atPath: systemCategoryListPath)
    }

    /// Settings categories reached by activating the `$SETTINGS` system row.
    static func settingsCategoryLabels(runtime: SWFMovieRuntime) -> [String] {
        entryLabels(runtime: runtime, atPath: settingsCategoryListPath)
    }

    // MARK: - Private

    private static func entryLabels(
        runtime: SWFMovieRuntime,
        atPath path: String
    ) -> [String] {
        guard
            let listNode = runtime.node(atPath: path, from: runtime.root),
            let entries = listNode.object.lookup(entryArrayName)?.property.value.objectValue
        else {
            return []
        }
        // `entryList` is an AS2 array, so its rows are numeric property names.
        // Sort numerically — lexical order would put row 10 before row 2.
        let indexed: [(Int, String)] = entries.ownPropertyNames.compactMap { name in
            guard let index = Int(name) else { return nil }
            return (index, name)
        }
        return indexed
            .sorted { $0.0 < $1.0 }
            .compactMap { _, name in
                guard
                    let row = entries.lookup(name)?.property.value.objectValue,
                    case let .string(text) = row.lookup("text")?.property.value
                else {
                    return nil
                }
                return text
            }
    }

    private static func showSystemPage(runtime: SWFMovieRuntime) {
        if
            let menu = runtime.node(atPath: menuPath, from: runtime.root),
            let systemPage = runtime.node(atPath: systemPagePath, from: runtime.root),
            let categoryList = runtime.node(
                atPath: systemCategoryListPath,
                from: runtime.root
            )
        {
            // The vanilla host normally seeds these through the tab-button
            // group before `SwitchPageToFront`. That group has no engine data
            // in OpenSky, so publish the same page/index pair explicitly.
            menu.object.assign(.object(systemPage.object), for: "TopmostPage")
            menu.object.assign(.integer(systemTabIndex), for: "iCurrentTab")
            runtime.focusTarget = categoryList
        }
        for path in [questsFaderPath, statsFaderPath] {
            runtime.callMovie("gotoAndStop", atPath: path, arguments: [.string("hide")])
        }
        runtime.callMovie(
            "gotoAndStop",
            atPath: systemFaderPath,
            arguments: [.string("forceFade")]
        )
    }

    private static func openSelectedSystemPage(runtime: SWFMovieRuntime) -> Bool {
        guard
            let list = runtime.node(atPath: systemCategoryListPath, from: runtime.root),
            case let .number(selected) =
            list.object.lookup("iSelectedIndex")?.property.value,
            selected == Double(settingsCategoryIndex),
            let state = runtime.runtime.registeredClass(named: "SystemPage")?
                .lookup("SETTINGS_CATEGORY_STATE")?.property.value
        else {
            return false
        }
        runtime.callMovie("StartState", atPath: systemPagePath, arguments: [state])
        runtime.focusTarget = runtime.node(
            atPath: settingsCategoryListPath,
            from: runtime.root
        )
        return true
    }

    private static func key(for event: MenuInputEvent) -> (code: Int, ascii: Int)? {
        switch event {
        case .move(.up): (SWFKeyCode.up, 0)
        case .move(.down): (SWFKeyCode.down, 0)
        case .move(.left): (SWFKeyCode.left, 0)
        case .move(.right): (SWFKeyCode.right, 0)
        case .button(.accept): (SWFKeyCode.enter, 13)
        case .button(.cancel): (SWFKeyCode.escape, 0)
        case .pointer: nil
        }
    }

    /// `SystemCategoriesList`'s backing array of row objects.
    static let entryArrayName = "EntriesA"
    static let settingsCategoryIndex = 4
}
