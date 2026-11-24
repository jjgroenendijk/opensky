// The measured AS2 contract of `Interface\craftingmenu.swf`, the station menu. The
// engine calls `/Menu.Initialize`, then fills `/Menu/InventoryLists` through `EntriesA`
// as the inventory movie does. The movie calls `CraftSelectedItem` or
// `CraftButtonPress` to craft and `CloseMenu` to leave. See docs/engine/crafting.md.

import Foundation
import OpenSkyFormatsSWF
import OpenSkyGameData

nonisolated public enum CraftingMenuMovieBridge: Sendable {
    public static let moviePath = "interface\\craftingmenu.swf"
    static let menuPath = "/Menu"
    static let layout = ItemListMovieLayout(listsPath: "\(menuPath)/InventoryLists")
    static let menuNamePath = "\(menuPath)/MenuNameHolder/MenuName"
    static let menuDescriptionPath = "\(menuPath)/MenuDescriptionHolder/MenuDescription"
    static let itemInfoPath = "\(menuPath)/ItemInfoHolder/ItemInfo"
    static let additionalDescriptionPath =
        "\(menuPath)/ItemInfoHolder/AdditionalDescriptionHolder/AdditionalDescription"
    static let bottomBarPath = "\(menuPath)/BottomBarInfo"
    /// Calls that change nothing in OpenSky: the 3D item view and the movie's own
    /// rename field.
    static let sinkHostFunctions = [
        "PlaySound", "myLog", "SetSelectedItem", "SetSelectedCategory", "ChooseItem",
        "ShowItem3D", "StartMouseRotation", "StopMouseRotation",
        "CanFadeItemInfo", "EndItemRename"
    ]

    static func prepare(
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
        runtime.registerHostFunction("AuxButtonPress") { _ in
            MainActor.assumeIsolated { onEvent(.aux) }
            return .undefined
        }
        runtime.registerHostFunction("CloseMenu") { _ in
            MainActor.assumeIsolated { onEvent(.close) }
            return .undefined
        }
        // `CalculateCharge([value])` as the slider moves, `SliderClose([accepted])` when it
        // closes; the kept value is the last one `CalculateCharge` sent.
        runtime.registerHostFunction("CalculateCharge") { call in
            let value = sliderValue(call.arguments.first)
            MainActor.assumeIsolated { onEvent(.sliderMoved(value)) }
            return .undefined
        }
        runtime.registerHostFunction("SliderClose") { call in
            let accepted = if case let .boolean(flag)? = call.arguments.first {
                flag
            } else {
                true
            }
            MainActor.assumeIsolated { onEvent(.sliderClosed(0, accepted: accepted)) }
            return .undefined
        }
    }

    /// `ShowSlider(maximum, minimum, value, snap)` opens the enchanting slider.
    static func showSlider(_ slider: EnchanterSlider, runtime: SWFMovieRuntime) {
        runtime.callMovie(
            "ShowSlider",
            atPath: menuPath,
            arguments: [slider.maximum, 1, slider.value, slider.step].map { .number(Double($0)) }
        )
    }

    private static func sliderValue(_ value: AS2Value?) -> Int {
        guard case let .number(number)? = value, number.isFinite else { return 0 }
        return Int(number.rounded())
    }

    /// `Initialize` builds the lists and the bottom bar; `bCanCraft` labels the button.
    static func activate(station: String, buttons: CraftingMenuButtons, runtime: SWFMovieRuntime) {
        runtime.callMovie("Initialize", atPath: menuPath)
        runtime.callMovie(
            "SetPlatform",
            arguments: [.number(SystemMenuMovieBridge.pcPlatform), .boolean(false)]
        )
        MenuMovieText.set(station, atPath: menuNamePath, runtime: runtime)
        publish(buttons, runtime: runtime)
    }

    /// The `bCanCraft` setter runs `UpdateButtonText`, which reads `ButtonText`.
    static func publish(_ buttons: CraftingMenuButtons, runtime: SWFMovieRuntime) {
        let labels = runtime.runtime.makeArray(buttons.labels.map(AS2Value.string))
        MenuMovieText.assign(
            .object(labels),
            member: "ButtonText",
            atPath: menuPath,
            runtime: runtime
        )
        MenuMovieText.assign(
            .boolean(buttons.canCraft), member: "bCanCraft", atPath: menuPath, runtime: runtime
        )
    }
}
