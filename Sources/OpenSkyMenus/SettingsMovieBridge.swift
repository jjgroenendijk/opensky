// The Settings page of `quest_journal.swf`, mirrored from the engine. Measured with
// `openskycli swf system-menu`: a category asks the host with
// `RequestGameplayOptions`, `RequestDisplayOptions`, or `RequestAudioOptions`
// and its list rows carry `text`, `movieType`, `value`, and stepper `options`.

import Foundation
import OpenSkyFormatsSWF
import OpenSkyGameData

nonisolated public enum SettingsMovieBridge: Sendable {
    public static let optionsListPath =
        "\(SystemMenuMovieBridge.systemPagePath)/OptionsListsPanel/OptionsLists/List_mc"

    public static let requestNames: [String: PlayerSettingGroup] = [
        "RequestGameplayOptions": .gameplay,
        "RequestDisplayOptions": .display,
        "RequestAudioOptions": .audio
    ]

    /// `SystemPage` state constants this bridge starts by name.
    public static let categoryState = "SETTINGS_CATEGORY_STATE"
    public static let optionsState = "OPTIONS_LISTS_STATE"
    public static let mainState = "MAIN_STATE"

    /// The movie's requests are answered by the engine's own publish, because the
    /// options list takes no key input in this runtime. The handler only reports.
    public static func register(
        runtime: SWFMovieRuntime,
        onRequest: @escaping @MainActor @Sendable (PlayerSettingGroup) -> Void
    ) {
        for (name, group) in requestNames {
            runtime.registerHostFunction(name) { _ in
                MainActor.assumeIsolated { onRequest(group) }
                return .undefined
            }
        }
    }

    // MARK: - Values

    /// The `value` a row shows: checkbox 0 or 1, stepper option index, slider 0 to 1.
    /// The settings store keeps every value in these units already.
    public static func movieValue(
        _ value: Double,
        for definition: PlayerSettingDefinition
    ) -> Double {
        definition.clamp(value) ?? definition.defaultValue
    }

    // MARK: - Publishing

    /// Replaces the option rows, selects one, and rebuilds the list.
    public static func publish(
        _ rows: [(definition: PlayerSettingDefinition, value: Double)],
        selected: Int,
        runtime: SWFMovieRuntime
    ) {
        let fields: [[String: AS2Value]] = rows.map { row in
            var fields: [String: AS2Value] = [
                "text": .string(row.definition.title),
                "movieType": .integer(row.definition.kind.movieType),
                "value": .number(movieValue(row.value, for: row.definition))
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

    /// Starts a `SystemPage` state by its constant name; the options state also
    /// focuses the options list.
    public static func startState(_ name: String, runtime: SWFMovieRuntime) {
        guard
            let value = runtime.runtime.registeredClass(named: "SystemPage")?
                .lookup(name)?.property.value
        else { return }
        runtime.callMovie(
            "StartState",
            atPath: SystemMenuMovieBridge.systemPagePath,
            arguments: [value]
        )
        let focus = name == optionsState
            ? optionsListPath : SystemMenuMovieBridge.settingsCategoryListPath
        runtime.focusTarget = runtime.node(atPath: focus, from: runtime.root)
    }
}
