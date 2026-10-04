// The player's settings as a pure value: stored values over catalog defaults, and
// key binding overrides. The JSON codec carries a schema version and steps old
// files forward. Bad stored values fall back to the default.

import Foundation

nonisolated public struct PlayerSettingsModel: Equatable, Sendable {
    public static let schemaVersion = 2

    /// Only values that differ from their default are kept.
    public private(set) var values: [PlayerSettingID: Double] = [:]
    /// Key binding overrides: `"<context>|<event>"` to a DirectInput scan code.
    public private(set) var keyBindings: [String: Int] = [:]

    public init() {}

    public func value(_ id: PlayerSettingID, in catalog: PlayerSettingsCatalog) -> Double {
        let fallback = catalog.definition(id)?.defaultValue ?? 0
        return values[id] ?? fallback
    }

    /// Stores a clamped value. Returns false when nothing changed or the id is unknown.
    @discardableResult
    public mutating func set(
        _ id: PlayerSettingID, to raw: Double, in catalog: PlayerSettingsCatalog
    ) -> Bool {
        guard let definition = catalog.definition(id), let value = definition.clamp(raw) else {
            return false
        }
        let before = self.value(id, in: catalog)
        if value == definition.defaultValue {
            values[id] = nil
        } else {
            values[id] = value
        }
        return before != value
    }

    public mutating func replaceKeyBindings(_ bindings: [String: Int]) {
        keyBindings = bindings
    }
}

// MARK: - Storage

nonisolated public enum PlayerSettingsCodecError: Error, Equatable, Sendable {
    case notAnObject
    case newerSchema(Int)
}

nonisolated extension PlayerSettingsModel {
    /// Sorted keys, so the same settings always write the same bytes.
    public func encoded() -> Data {
        let document: [String: Any] = [
            "schema": Self.schemaVersion,
            "values": Dictionary(uniqueKeysWithValues: values.map { ($0.key.rawValue, $0.value) }),
            "keyBindings": keyBindings
        ]
        return (try? JSONSerialization.data(
            withJSONObject: document, options: [.sortedKeys, .prettyPrinted]
        )) ?? Data()
    }

    /// Unknown ids, non-numbers, and out-of-range values are dropped one by one, so
    /// one bad value never costs the rest.
    public init(decoding data: Data, catalog: PlayerSettingsCatalog) throws {
        self.init()
        guard
            let document = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw PlayerSettingsCodecError.notAnObject
        }
        let schema = (document["schema"] as? Int) ?? 1
        guard schema <= Self.schemaVersion else {
            throw PlayerSettingsCodecError.newerSchema(schema)
        }
        let migrated = schema == 1 ? Self.migrateFromSchema1(document) : document
        for (key, raw) in migrated["values"] as? [String: Any] ?? [:] {
            guard let number = (raw as? NSNumber)?.doubleValue else { continue }
            set(PlayerSettingID(key), to: number, in: catalog)
        }
        for (key, raw) in migrated["keyBindings"] as? [String: Any] ?? [:] {
            guard let code = raw as? Int, (0 ... 0xFF).contains(code) else { continue }
            keyBindings[key] = code
        }
    }

    /// Schema 1 kept every value at the top level, with no key bindings.
    static func migrateFromSchema1(_ document: [String: Any]) -> [String: Any] {
        var values = document
        values.removeValue(forKey: "schema")
        return ["schema": schemaVersion, "values": values, "keyBindings": [String: Int]()]
    }
}
