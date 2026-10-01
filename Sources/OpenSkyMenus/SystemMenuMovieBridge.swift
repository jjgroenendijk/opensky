// The measured AS2 contract of `Interface\quest_journal.swf`, the system menu.
// It has no AppKit and no renderer, so the CLI builds it and tests drive it with
// synthetic AS2. The selector it shows is SystemMenuModel.swift.

import Foundation
import OpenSkyFormatsSWF

nonisolated public enum SystemMenuMovieBridge: Sendable {
    public static let moviePath = "interface\\quest_journal.swf"
    /// Ticks the top-level fade needs to settle after `ShowMenu`, measured
    /// against the install.
    public static let activationTicks = 20
    /// The `QuestJournalBase` instance. Page switching is a direct method on
    /// this clip; engine lifecycle calls are `GameDelegate` callbacks.
    public static let menuPath = "/QuestJournalFader/Menu_mc"
    public static let systemPagePath = "\(menuPath)/SystemFader/Page_mc"
    public static let systemCategoryListPath = "\(systemPagePath)/CategoryList_mc/List_mc"
    public static let settingsCategoryListPath = "\(systemPagePath)/SettingsPanel/List_mc"
    public static let systemFaderPath = "\(menuPath)/SystemFader"
    public static let questsFaderPath = "\(menuPath)/QuestsFader"
    public static let statsFaderPath = "\(menuPath)/StatsFader"

    /// `PLATFORM_PC_KBMOUSE`, the value the movie's platform switch expects for
    /// keyboard and mouse.
    public static let pcPlatform = 0.0

    /// Movie-to-engine calls that do not mutate OpenSky state yet. The boolean
    /// queries return false; the rest are notifications or requests whose data
    /// consumers are outside the system-page surface.
    public static let sinkHostFunctions = [
        "myLog", "PlaySound", "PlayOKSound", "RememberCurrentTabIndex",
        "RequestPlayerInfo"
    ]
    public static let falseHostFunctions = ["ShouldShowMod", "GetIsRemoteDevice"]

    /// Scaleform's UI-sound hook, which the movie reaches for as a plain
    /// `_global` function rather than through `GameDelegate`. OpenSky has no UI
    /// sound bank yet, so it is a no-op rather than a missing name.
    public static let globalSinkFunctions = ["gfxProcessSound"]

    /// `PageArray` is `[Quests, Stats, System]`, measured from the live movie.
    public static let systemTabIndex = 2

    // MARK: - Bring-up

    /// Installs the surface the movie reaches for *during* `start()`. Bring-up
    /// is the first thing that calls out to the host, so this must run before
    /// the runtime is started (`Renderer.startSWFRuntime(prepare:)`).
    public static func prepare(runtime: SWFMovieRuntime) {
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
    public static func activate(
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
    public static func handle(_ event: MenuInputEvent, runtime: SWFMovieRuntime) -> Bool {
        if
            case .button(.accept) = event,
            openSelectedSystemPage(runtime: runtime)
        {
            return true
        }
        guard let key = event.swfKey else {
            return false
        }
        let down = runtime.handle(.keyDown(code: key.code, ascii: key.ascii))
        let up = runtime.handle(.keyUp(code: key.code))
        return down || up
    }

    // MARK: - Readout

    /// Faults and distinct unresolved names, for the verification readout.
    public static func diagnostics(runtime: SWFMovieRuntime) -> (faults: Int, missingNames: Int) {
        let tally = runtime.tally
        return (tally.faultTotal, tally.missingNames.count)
    }

    /// The page brought to the front, derived from the actual System category
    /// rows rather than a bridge-owned flag.
    public static func currentState(runtime: SWFMovieRuntime) -> String? {
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
    public static func entryLabels(runtime: SWFMovieRuntime) -> [String] {
        MenuMovieEntryList.labels(atPath: systemCategoryListPath, runtime: runtime)
    }

    /// Settings categories reached by activating the `$SETTINGS` system row.
    public static func settingsCategoryLabels(runtime: SWFMovieRuntime) -> [String] {
        MenuMovieEntryList.labels(atPath: settingsCategoryListPath, runtime: runtime)
    }

    // MARK: - Private

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

    /// `SystemCategoriesList`'s backing array of row objects.
    public static let entryArrayName = MenuMovieEntryList.arrayName
    public static let settingsCategoryIndex = 4
}
