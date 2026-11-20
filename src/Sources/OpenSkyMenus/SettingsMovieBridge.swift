// The Settings page of `quest_journal.swf`. The movie runs the page; a category asks
// the host with `RequestGameplayOptions`, `RequestDisplayOptions`, or
// `RequestAudioOptions` and passes its rows, with `text`, `movieType`, and stepper
// `options` (docs/engine/system-menu.md).

import Foundation
public import OpenSkyFormatsSWF
import OpenSkyGameData

nonisolated public enum SettingsMovieBridge: Sendable {
    static let optionsListPath =
        "\(SystemMenuMovieBridge.systemPagePath)/OptionsListsPanel/OptionsLists/List_mc"

    static let categoryListPath = "\(SystemMenuMovieBridge.systemPagePath)/SettingsPanel/List_mc"

    static let requestNames: [String: PlayerSettingGroup] = [
        "RequestGameplayOptions": .gameplay,
        "RequestDisplayOptions": .display,
        "RequestAudioOptions": .audio
    ]

    /// Rows the game leaves without an `ID` on a computer, so the movie drops them.
    static let hiddenRows: Set<PlayerSettingID> = [PlayerSettingID("gameplay.useKinect")]

    /// `OptionChange([ID, value])`: a row's own stepper, slider, or check box changed,
    /// as a click, an arrow key, or the Defaults button does.
    static let optionChangeName = "OptionChange"

    /// One engine row of a category. `id` is its index in the category, which the
    /// movie hands back in `OptionChange`.
    struct Row: Sendable {
        let id: Int
        let definition: PlayerSettingDefinition
        let value: Double
    }

    /// The movie builds a category's rows and passes them in its request. The engine
    /// fills each row's value during the call, because the same script then drops
    /// the rows without an `ID` and draws the list.
    static func register(
        runtime: SWFMovieRuntime,
        onRequest: @escaping @MainActor @Sendable (PlayerSettingGroup) -> [Row],
        onChange: @escaping @MainActor @Sendable (Int, Double) -> Void
    ) {
        for (name, group) in requestNames {
            runtime.registerHostFunction(name) { call in
                let rows = MainActor.assumeIsolated { onRequest(group) }
                if let list = call.arguments.lazy.compactMap(\.objectValue).first {
                    fill(list, with: rows, runtime: call.movie.runtime)
                }
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

    /// The CLI's way in: each category gets the default values, and changes are dropped.
    @MainActor public static func registerDefaults(runtime: SWFMovieRuntime) {
        let store = PlayerSettingsStore(persistence: nil)
        let page = SettingsPageModel(catalog: store.catalog)
        var rows: [PlayerSettingGroup: [Row]] = [:]
        for group in SettingsPageModel.categories {
            for (index, id) in (page.catalog[group] ?? []).enumerated()
                where !hiddenRows.contains(id)
            {
                guard let definition = store.catalog.definition(id) else { continue }
                rows[group, default: []].append(
                    Row(id: index, definition: definition, value: store.value(id))
                )
            }
        }
        register(runtime: runtime, onRequest: { rows[$0] ?? [] }, onChange: { _, _ in })
    }

    /// Gives each movie row whose `text` names an engine row its `ID`, `value`, and
    /// `defaultVal`. Engine rows the movie lacks, such as the sound category volumes,
    /// are added at the end.
    static func fill(_ list: AS2Object, with rows: [Row], runtime: AS2Runtime) {
        var unmatched = rows
        for entry in list.elements.compactMap(\.objectValue) {
            guard
                case let .string(text) = entry.lookup("text")?.property.value,
                let index = unmatched.firstIndex(where: { $0.definition.title == text })
            else { continue }
            assign(unmatched.remove(at: index), to: entry)
        }
        for row in unmatched {
            let entry = runtime.makeObject()
            entry.assign(.string(row.definition.title), for: "text")
            entry.assign(.integer(row.definition.kind.movieType), for: "movieType")
            if case let .choice(options) = row.definition.kind {
                entry.assign(
                    .object(runtime.makeArray(options.map(AS2Value.string))), for: "options"
                )
            }
            assign(row, to: entry)
            list.setElement(.object(entry), at: list.arrayLength ?? 0)
        }
    }

    private static func assign(_ row: Row, to entry: AS2Object) {
        entry.assign(.integer(row.id), for: "ID")
        entry.assign(.number(movieValue(row.value, for: row.definition)), for: "value")
        entry.assign(.number(row.definition.defaultValue), for: "defaultVal")
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

    /// The `value` a row shows: checkbox 0 or 1, stepper option index, slider 0 to 1.
    /// The settings store keeps every value in these units already.
    static func movieValue(
        _ value: Double,
        for definition: PlayerSettingDefinition
    ) -> Double {
        definition.clamp(value) ?? definition.defaultValue
    }

    /// The `ID` of each row the options list shows, in row order, and its highlight.
    static func shownRows(runtime: SWFMovieRuntime) -> (ids: [Int], selected: Int)? {
        guard
            let list = runtime.node(atPath: optionsListPath, from: runtime.root),
            let entries = list.object.lookup(MenuMovieEntryList.arrayName)?.property.value
                .objectValue
        else { return nil }
        let ids = entries.elements.compactMap { entry -> Int? in
            guard case let .number(id)? = entry.objectValue?.lookup("ID")?.property.value else {
                return nil
            }
            return Int(exactly: id)
        }
        let selected = InventoryMenuMovieBridge.selectedIndex(
            runtime: runtime,
            atPath: optionsListPath
        )
        return (ids, selected ?? -1)
    }
}
