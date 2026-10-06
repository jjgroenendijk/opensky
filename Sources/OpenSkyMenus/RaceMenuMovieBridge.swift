// The measured AS2 contract of `Interface\racesex_menu.swf`, the race menu. The
// engine sends the categories, the races, and one slider per face value; a slider
// calls the engine back with its new position. See docs/engine/race-menu.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsSWF

nonisolated public enum RaceMenuMovieBridge: Sendable {
    public static let moviePath = "interface\\racesex_menu.swf"
    /// Movie-to-engine calls that only report sounds, camera zoom, and text focus.
    public static let sinkHostFunctions = [
        "ZoomPC", "SetAllowTextInput", "ShowVirtualKeyboard", "PlaySound", "myLog"
    ]
    /// Slider callbacks the movie may name; each is answered as a slider change.
    public static let sliderHostFunctions = [
        "ChangeDoubleMorph", "ChangeWeight", "ChangeHeadPart", "ChangeHeadPreset",
        "ChangeTintingMask", "ChangeFaceDetails", "ChangePreset", "ChangeHairColorPreset"
    ]
    /// A slider shows under each category whose flag it shares (`filterFlag & flag`).
    static let raceCategory = 1
    static let bodyCategory = 2
    static let headCategory = 4

    public enum Request: Equatable, Sendable {
        case race(Int)
        /// `id` is the slider's row in `RaceMenuModel.rows`.
        case slider(id: Int, value: Double)
        case name(String)
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
        forward("ConfirmDone") { _, _ in .done }
    }

    /// Sends the categories, races, sliders, and name the model holds.
    public static func publish(_ model: RaceMenuModel, runtime: SWFMovieRuntime) {
        runtime.callMovie("SetCategoriesList", arguments: [
            .string("$RACE"), .integer(raceCategory), .string("$BODY"), .integer(bodyCategory),
            .string("$HEAD"), .integer(headCategory)
        ])
        runtime.callMovie("SetRaceList", arguments: model.races.flatMap { race in
            [
                .string(race.name), .string(""),
                .integer(race.formID == model.identity.race ? 1 : 0)
            ]
        })
        let sliders = model.rows.enumerated().flatMap { item in
            slider(id: item.offset, row: item.element, model: model)
        }
        runtime.callMovie("SetSliders", arguments: sliders)
        runtime.callMovie("SetNameText", arguments: [.string(model.identity.name)])
    }

    /// Eight values per slider: text, filter flag, callback, min, max, position,
    /// interval, and id. Rows without a slider send nothing.
    static func slider(id: Int, row: RaceMenuRow, model: RaceMenuModel) -> [AS2Value] {
        let face = model.identity.face
        let spec: SliderSpec
        switch row {
        case .weight:
            spec = SliderSpec(
                flag: bodyCategory,
                callback: "ChangeWeight",
                range: 0 ... 100,
                value: Double(face.weight),
                step: 5
            )
        case let .slider(index):
            spec = SliderSpec(
                flag: headCategory,
                callback: "ChangeDoubleMorph",
                range: -1 ... 1,
                value: Double(face.morphs[index]),
                step: 0.1
            )
        case let .part(index):
            guard let range = RaceMenuModel.partRanges[index] else { return [] }
            let bounds = Double(range.lowerBound) ... Double(range.upperBound)
            spec = SliderSpec(
                flag: headCategory,
                callback: "ChangeHeadPart",
                range: bounds,
                value: Double(face.parts[index]),
                step: 1
            )
        case .race, .sex, .name:
            return []
        }
        return [
            .string(model.label(row)), .integer(spec.flag), .string(spec.callback),
            .number(spec.range.lowerBound), .number(spec.range.upperBound), .number(spec.value),
            .number(spec.step), .integer(id)
        ]
    }

    @discardableResult
    public static func handle(_ event: MenuInputEvent, runtime: SWFMovieRuntime) -> Bool {
        guard let key = event.swfKey else { return false }
        let down = runtime.handle(.keyDown(code: key.code, ascii: key.ascii))
        let up = runtime.handle(.keyUp(code: key.code))
        return down || up
    }
}

private struct SliderSpec {
    let flag: Int
    let callback: String
    let range: ClosedRange<Double>
    let value: Double
    let step: Double
}
