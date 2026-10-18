// The measured AS2 contract of `Interface\craftingmenu.swf`, the station menu. The
// engine calls `/Menu.Initialize`, then fills `/Menu/InventoryLists` through `EntriesA`
// as the inventory movie does. The movie calls `CraftSelectedItem` or
// `CraftButtonPress` to craft and `CloseMenu` to leave. See docs/engine/crafting.md.

import Foundation
import OpenSkyFormatsSWF

nonisolated public enum CraftingMenuMovieBridge: Sendable {
    public static let moviePath = "interface\\craftingmenu.swf"
    public static let menuPath = "/Menu"
    public static let layout = ItemListMovieLayout(listsPath: "\(menuPath)/InventoryLists")
    public static let menuNamePath = "\(menuPath)/MenuNameHolder/MenuName"
    /// Calls that change nothing in OpenSky: the 3D item view, renaming, and the
    /// enchanting charge slider.
    public static let sinkHostFunctions = [
        "PlaySound", "myLog", "SetSelectedItem", "SetSelectedCategory", "ChooseItem",
        "ShowItem3D", "StartMouseRotation", "StopMouseRotation", "AuxButtonPress",
        "CanFadeItemInfo", "EndItemRename", "CalculateCharge", "SliderClose"
    ]

    public static func prepare(
        runtime: SWFMovieRuntime,
        onEvent: @escaping @MainActor @Sendable (ItemListMovieEvent) -> Void
    ) {
        for name in sinkHostFunctions {
            runtime.registerHostFunction(name) { _ in .undefined }
        }
        for name in ["CraftSelectedItem", "CraftButtonPress"] {
            runtime.registerHostFunction(name) { _ in
                MainActor.assumeIsolated { onEvent(.select) }
                return .undefined
            }
        }
        runtime.registerHostFunction("CloseMenu") { _ in
            MainActor.assumeIsolated { onEvent(.close) }
            return .undefined
        }
    }

    /// `Initialize` builds the lists and the bottom bar; `bCanCraft` labels the button.
    public static func activate(station: String, runtime: SWFMovieRuntime) {
        runtime.callMovie("Initialize", atPath: menuPath)
        runtime.callMovie(
            "SetPlatform",
            arguments: [.number(SystemMenuMovieBridge.pcPlatform), .boolean(false)]
        )
        MenuMovieText.set(station, atPath: menuNamePath, runtime: runtime)
        MenuMovieText.assign(
            .boolean(true), member: "bCanCraft", atPath: menuPath, runtime: runtime
        )
    }
}
