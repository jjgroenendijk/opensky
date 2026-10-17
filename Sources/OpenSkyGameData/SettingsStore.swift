// Typed user settings over the shared defaults domain, so the app and the CLI read
// and write the same values. A key names its type and the value a missing entry
// reads as.

import Foundation

/// A value a setting can hold.
nonisolated public protocol SettingValue: Sendable {
    static func read(_ name: String, from defaults: UserDefaults) -> Self?
    func write(_ name: String, to defaults: UserDefaults)
}

nonisolated public struct SettingKey<Value: SettingValue>: Sendable {
    public let name: String
    public let defaultValue: Value

    public init(_ name: String, default defaultValue: Value) {
        self.name = name
        self.defaultValue = defaultValue
    }
}

nonisolated public struct SettingsStore {
    public let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The shared domain (`GameDataLocator.settingsDefaults`).
    public static var shared: SettingsStore {
        SettingsStore(defaults: GameDataLocator.settingsDefaults)
    }

    public func value<Value>(_ key: SettingKey<Value>) -> Value {
        Value.read(key.name, from: defaults) ?? key.defaultValue
    }

    /// The stored value, or nil when the user never chose one.
    public func storedValue<Value>(_ key: SettingKey<Value>) -> Value? {
        Value.read(key.name, from: defaults)
    }

    public func set<Value>(_ value: Value, for key: SettingKey<Value>) {
        value.write(key.name, to: defaults)
    }

    public func isOverridden(_ key: SettingKey<some SettingValue>) -> Bool {
        defaults.object(forKey: key.name) != nil
    }

    public func reset(_ key: SettingKey<some SettingValue>) {
        defaults.removeObject(forKey: key.name)
    }

    /// Copies each named value the shared domain lacks from `old`, then removes it
    /// there. Older CLI builds wrote some settings to their own domain.
    public func migrate(_ names: [String], from old: UserDefaults) {
        guard old !== defaults else { return }
        for name in names {
            guard let value = old.object(forKey: name) else { continue }
            if defaults.object(forKey: name) == nil {
                defaults.set(value, forKey: name)
            }
            old.removeObject(forKey: name)
        }
    }
}

nonisolated extension Bool: SettingValue {
    public static func read(_ name: String, from defaults: UserDefaults) -> Bool? {
        defaults.object(forKey: name) == nil ? nil : defaults.bool(forKey: name)
    }

    public func write(_ name: String, to defaults: UserDefaults) {
        defaults.set(self, forKey: name)
    }
}

nonisolated extension Double: SettingValue {
    public static func read(_ name: String, from defaults: UserDefaults) -> Double? {
        defaults.object(forKey: name) == nil ? nil : defaults.double(forKey: name)
    }

    public func write(_ name: String, to defaults: UserDefaults) {
        defaults.set(self, forKey: name)
    }
}

nonisolated extension String: SettingValue {
    public static func read(_ name: String, from defaults: UserDefaults) -> String? {
        defaults.string(forKey: name)
    }

    public func write(_ name: String, to defaults: UserDefaults) {
        defaults.set(self, forKey: name)
    }
}
