// The Settings page of `quest_journal.swf`, mirrored from the engine. Measured with
// `openskycli menu system`: a category asks the host with
// `RequestGameplayOptions`, `RequestDisplayOptions`, or `RequestAudioOptions`
// and its list rows carry `text`, `movieType`, `value`, and stepper `options`.

import Foundation
import OpenSkyFormatsSWF
import OpenSkyGameData

nonisolated enum SettingsMovieBridge: Sendable {
    static let optionsListPath =
        "\(SystemMenuMovieBridge.systemPagePath)/OptionsListsPanel/OptionsLists/List_mc"

    static let requestNames: [String: PlayerSettingGroup] = [
        "RequestGameplayOptions": .gameplay,
        "RequestDisplayOptions": .display,
        "RequestAudioOptions": .audio
    ]

    /// `SystemPage` state constants this bridge starts by name.
    static let categoryState = "SETTINGS_CATEGORY_STATE"
    static let optionsState = "OPTIONS_LISTS_STATE"
    static let mainState = "MAIN_STATE"

    /// `OptionChange([ID, value])`: a row's own stepper, slider, or check box changed,
    /// as a click or the Defaults button does.
    static let optionChangeName = "OptionChange"

    /// The movie's requests are answered by the engine's own publish. A change the
    /// movie made itself, with the cursor, reports the row and its new value.
    static func register(
        runtime: SWFMovieRuntime,
        onRequest: @escaping @MainActor @Sendable (PlayerSettingGroup) -> Void,
        onChange: @escaping @MainActor @Sendable (Int, Double) -> Void
    ) {
        for (name, group) in requestNames {
            runtime.registerHostFunction(name) { _ in
                MainActor.assumeIsolated { onRequest(group) }
                return .undefined
            }
        }
        runtime.registerHostFunction(optionChangeName) { call in
            guard let change = optionChange(call.arguments) else {
                return .undefined
            }
            MainActor.assumeIsolated { onChange(change.row, change.value) }
            return .undefined
        }
    }

    /// The row and value of an `OptionChange` call, which passes them as two numbers.
    static func optionChange(_ arguments: [AS2Value]) -> (row: Int, value: Double)? {
        let numbers = arguments.map(number)
        guard numbers.count >= 2, numbers[1].isFinite else { return nil }
        let id = numbers[0]
        guard id.isFinite, id >= 0, id == id.rounded() else { return nil }
        return (Int(id), numbers[1])
    }

    private static func number(_ value: AS2Value) -> Double {
        if case let .number(number) = value {
            return number
        }
        return .nan
    }

    // MARK: - Values

    /// The `value` a row shows: checkbox 0 or 1, stepper option index, slider 0 to 1.
    /// The settings store keeps every value in these units already.
    static func movieValue(
        _ value: Double,
        for definition: PlayerSettingDefinition
    ) -> Double {
        definition.clamp(value) ?? definition.defaultValue
    }

    // MARK: - Publishing

    /// Replaces the option rows, selects one, and rebuilds the list.
    static func publish(
        _ rows: [(definition: PlayerSettingDefinition, value: Double)],
        selected: Int,
        runtime: SWFMovieRuntime
    ) {
        let fields: [[String: AS2Value]] = rows.enumerated().map { index, row in
            var fields: [String: AS2Value] = [
                "text": .string(row.definition.title),
                "movieType": .integer(row.definition.kind.movieType),
                "value": .number(movieValue(row.value, for: row.definition)),
                // The row's `ID` comes back in `OptionChange`; `defaultVal` is what
                // the movie's Defaults button sets.
                "ID": .integer(index),
                "defaultVal": .number(row.definition.defaultValue)
            ]
            if case let .choice(options) = row.definition.kind {
                fields["options"] = .object(runtime.runtime.makeArray(options.map(AS2Value.string)))
            }
            return fields
        }
        MenuMovieEntryList.publish(fields, atPath: optionsListPath, runtime: runtime)
        if let list = runtime.node(atPath: optionsListPath, from: runtime.root) {
            list.object.assign(.integer(selected), for: "iSelectedIndex")
        }
        runtime.callMovie("InvalidateData", atPath: optionsListPath)
    }

    /// Starts a `SystemPage` state by its constant name. The movie focuses the
    /// state's list itself.
    static func startState(_ name: String, runtime: SWFMovieRuntime) {
        guard
            let value = runtime.runtime.registeredClass(named: "SystemPage")?
                .lookup(name)?.property.value
        else { return }
        runtime.callMovie(
            "StartState",
            atPath: SystemMenuMovieBridge.systemPagePath,
            arguments: [value]
        )
    }
}

extension PlayerSettingsStore {
    /// The rows the Settings list shows for `ids`, each with its definition and value.
    func movieRows(
        _ ids: [PlayerSettingID]
    ) -> [(definition: PlayerSettingDefinition, value: Double)] {
        ids.compactMap { id in catalog.definition(id).map { (definition: $0, value: value(id)) } }
    }
}
