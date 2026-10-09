// The player's settings as a pure value: stored values over catalog defaults, and
// key binding overrides. The JSON codec carries a schema version and steps old
// files forward. Bad stored values fall back to the default.

import Foundation

nonisolated public struct PlayerSettingsModel: Equatable, Sendable {
    public static let schemaVersion = 3

    /// Only values that differ from their default are kept.
    public private(set) var values: [PlayerSettingID: Double] = [:]
    /// Key binding overrides: `"<context>|<event>"` to a DirectInput scan code.
    public private(set) var keyBindings: [String: Int] = [:]
    /// Text values, such as a folder path. Empty text means the default.
    public private(set) var texts: [PlayerSettingID: String] = [:]

    public init() {}

    public func text(_ id: PlayerSettingID) -> String? {
        texts[id]
    }

    /// Returns false when nothing changed or the id is not a text setting.
    @discardableResult
    public mutating func setText(_ id: PlayerSettingID, to text: String?) -> Bool {
        guard PlayerSettingsCatalog.textSettingIDs.contains(id) else { return false }
        let stored = text?.isEmpty == false ? text : nil
        guard texts[id] != stored else { return false }
        texts[id] = stored
        return true
    }

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
            "keyBindings": keyBindings,
            "texts": Dictionary(uniqueKeysWithValues: texts.map { ($0.key.rawValue, $0.value) })
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
        let current = schema == 1 ? Self.migrateFromSchema1(document) : document
        let migrated = schema < 3 ? Self.migrateFromSchema2(current) : current
        for (key, raw) in migrated["values"] as? [String: Any] ?? [:] {
            guard let number = (raw as? NSNumber)?.doubleValue else { continue }
            set(PlayerSettingID(key), to: number, in: catalog)
        }
        for (key, raw) in migrated["keyBindings"] as? [String: Any] ?? [:] {
            guard let code = raw as? Int, (0 ... 0xFF).contains(code) else { continue }
            keyBindings[key] = code
        }
        for (key, raw) in migrated["texts"] as? [String: Any] ?? [:] {
            guard let text = raw as? String else { continue }
            setText(PlayerSettingID(key), to: text)
        }
    }

    /// Schema 2 named the asset optimisation settings `assetCache`. Its three presets
    /// become texture qualities: Best performance is Medium; Balanced and Highest
    /// quality are Original, because Balanced saved no space. The size limit is gone.
    /// The texture budget gained Automatic at index 0, so a fixed choice moves up one.
    static func migrateFromSchema2(_ document: [String: Any]) -> [String: Any] {
        var result = document
        var values: [String: Any] = [:]
        for (key, value) in document["values"] as? [String: Any] ?? [:] {
            if key == "assetCache.preset" {
                let preset = (value as? NSNumber)?.intValue
                values["assetOptimisation.textureQuality"] = preset == 0 ? 2 : 0
            } else if key == "rendering.textureBudget", let index = (value as? NSNumber)?.intValue {
                values[key] = index + 1
            } else if key != "assetCache.limitGiB" {
                values[PlayerSettingsCatalog.renamedIDs[key] ?? key] = value
            }
        }
        var texts: [String: Any] = [:]
        for (key, value) in document["texts"] as? [String: Any] ?? [:] {
            texts[PlayerSettingsCatalog.renamedIDs[key] ?? key] = value
        }
        result["values"] = values
        result["texts"] = texts
        result["schema"] = schemaVersion
        return result
    }

    /// Schema 1 kept every value at the top level, with no key bindings.
    static func migrateFromSchema1(_ document: [String: Any]) -> [String: Any] {
        var values = document
        values.removeValue(forKey: "schema")
        return ["schema": schemaVersion, "values": values, "keyBindings": [String: Int]()]
    }
}
