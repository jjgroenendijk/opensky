// The measured AS2 contract of `Interface\racesex_menu.swf`, the race menu. The
// engine sends the categories, the races, and one slider per face value; a slider
// calls the engine back with its new position. See docs/engine/race-menu.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsSWF

nonisolated public enum RaceMenuMovieBridge: Sendable {
    public static let moviePath = "interface\\racesex_menu.swf"
    /// Movie-to-engine calls that only report sounds and text focus.
    public static let sinkHostFunctions = [
        "SetAllowTextInput", "ShowVirtualKeyboard", "PlaySound", "myLog"
    ]
    /// Slider callbacks the engine names; each is answered as a slider change. The
    /// movie's own test list uses the vanilla ones, so the same names are kept.
    public static let sliderHostFunctions = [
        "ChangeDoubleMorph", "ChangeWeight", "ChangeHeadPart", "ChangeHeadPreset",
        "ChangeTintingMask", "ChangeFaceDetails", "ChangePreset", "ChangeHairColorPreset",
        "ChangeSex"
    ]
    static let pcPlatform = SystemMenuMovieBridge.pcPlatform

    public enum Request: Equatable, Sendable {
        case race(Int)
        /// `id` is the slider's row in `RaceMenuModel.rows`.
        case slider(id: Int, value: Double)
        case name(String)
        /// `ZoomPC(true)` on the Race and Head categories, `false` on Body.
        case zoom(Bool)
        case done
    }

    public static func prepare(
        runtime: SWFMovieRuntime,
        onRequest: @escaping @MainActor @Sendable (Request) -> Void
    ) {
        for name in sinkHostFunctions {
            runtime.registerHostFunction(name) { _ in .undefined }
        }
        func forward(
            _ name: String,
            _ request: @escaping @Sendable ([Double], String?) -> Request?
        ) {
            runtime.registerHostFunction(name) { call in
                let numbers = call.arguments.compactMap { value -> Double? in
                    guard case let .number(number) = value, number.isFinite else { return nil }
                    return number
                }
                let text = call.arguments.lazy.compactMap { value -> String? in
                    guard case let .string(text) = value else { return nil }
                    return text
                }.first
                guard let request = request(numbers, text) else { return .undefined }
                MainActor.assumeIsolated { onRequest(request) }
                return .undefined
            }
        }
        forward("ChangeRace") { numbers, _ in numbers.first.map { .race(Int($0)) } }
        for name in sliderHostFunctions {
            forward(name) { numbers, _ in
                numbers.count >= 2 ? .slider(id: Int(numbers[1]), value: numbers[0]) : nil
            }
        }
        forward("ChangeName") { _, text in text.map { .name($0) } }
        runtime.registerHostFunction("ZoomPC") { call in
            let zoomIn: Bool? = switch call.arguments.first {
            case let .boolean(flag): flag
            case let .number(number): number != 0
            default: nil
            }
            guard let zoomIn else { return .undefined }
            MainActor.assumeIsolated { onRequest(.zoom(zoomIn)) }
            return .undefined
        }
        forward("ConfirmDone") { _, _ in .done }
    }

    /// Once the panels exist. The root forwards both to the panels, and `SetPlatform`
    /// makes each button attach its key art.
    public static func setPlatform(runtime: SWFMovieRuntime) {
        runtime.callMovie("SetPlatform", arguments: [.number(pcPlatform), .boolean(false)])
        runtime.callMovie("InitExtensions")
    }

    /// The panel path that holds the movie's lists in the vanilla race menu.
    static let panelsPath = "RaceSexMenuBaseInstance.RaceSexPanelsInstance"

    /// False when the movie's category list did not build, so the movie cannot show
    /// what `publish` sends and the engine rows must stay in charge.
    public static func listsBuilt(runtime: SWFMovieRuntime) -> Bool {
        guard
            let panels = runtime.node(atPath: panelsPath, from: runtime.root),
            let list = panels.object.lookup("_CategoriesList")?.property.value
        else { return false }
        switch list {
        case .undefined, .null: return false
        default: return true
        }
    }

    /// Sends the categories, races, sliders, and name the model holds.
    public static func publish(_ model: RaceMenuModel, runtime: SWFMovieRuntime) {
        runtime.callMovie("SetCategoriesList", arguments: RaceMenuCategory.allCases.flatMap {
            [AS2Value.string(model.labels.text($0.labelKey)), .integer($0.rawValue)]
        })
        runtime.callMovie("SetRaceList", arguments: model.races.flatMap { race in
            [
                .string(race.name), .string(race.description),
                .integer(race.formID == model.identity.race ? 1 : 0)
            ]
        })
        let sliders = model.rows.enumerated().flatMap { item in
            slider(id: item.offset, row: item.element, model: model)
        }
        runtime.callMovie("SetOptionSliders", arguments: sliders)
        runtime.callMovie("SetNameText", arguments: [.string(model.identity.name)])
    }

    /// Eight values per slider: text, filter flag, callback, min, max, position,
    /// interval, and id. The race and name rows have their own lists.
    static func slider(id: Int, row: RaceMenuRow, model: RaceMenuModel) -> [AS2Value] {
        guard
            let control = RaceMenuModel.control(for: row), control.category != .race,
            let range = model.range(row)
        else { return [] }
        return [
            .string(model.label(row)), .integer(control.category.rawValue),
            .string(callback(row)), .number(Double(range.bounds.lowerBound)),
            .number(Double(range.bounds.upperBound)), .number(Double(model.position(row))),
            .number(Double(range.step)), .integer(id)
        ]
    }

    static func callback(_ row: RaceMenuRow) -> String {
        switch row {
        case .weight: "ChangeWeight"
        case .slider: "ChangeDoubleMorph"
        case .part: "ChangePreset"
        case .headPreset: "ChangeHeadPreset"
        case .headPart: "ChangeHeadPart"
        case .hairColor: "ChangeHairColorPreset"
        case .complexion: "ChangeFaceDetails"
        case .tintColor, .tintMask: "ChangeTintingMask"
        case .sex: "ChangeSex"
        case .race, .name: ""
        }
    }

    @discardableResult
    public static func handle(_ event: MenuInputEvent, runtime: SWFMovieRuntime) -> Bool {
        guard let key = event.swfKey else { return false }
        let down = runtime.handle(.keyDown(code: key.code, ascii: key.ascii))
        let up = runtime.handle(.keyUp(code: key.code))
        return down || up
    }
}
