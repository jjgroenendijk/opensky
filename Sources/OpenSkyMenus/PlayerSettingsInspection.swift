// The sidebar's view of the settings store and the key bindings: each value
// beside its default, and keys that two actions share. Pure: values in, rows out.

import Foundation
import OpenSkyGameData

nonisolated public struct PlayerSettingRow: Equatable, Sendable {
    public let title: String
    public let value: String
    public let defaultValue: String
    public let isApplied: Bool

    public var isChanged: Bool {
        value != defaultValue
    }
}

nonisolated public struct KeyBindingRow: Equatable, Sendable {
    public let event: String
    public let key: String
    public let isOverride: Bool
}

nonisolated public enum PlayerSettingsInspection {
    @MainActor
    public static func rows(
        store: PlayerSettingsStore, group: PlayerSettingGroup
    ) -> [PlayerSettingRow] {
        store.catalog.definitions(in: group).map { definition in
            PlayerSettingRow(
                title: definition.title.hasPrefix("$")
                    ? String(definition.title.dropFirst()) : definition.title,
                value: text(store.value(definition.id), kind: definition.kind),
                defaultValue: text(definition.defaultValue, kind: definition.kind),
                isApplied: definition.isApplied
            )
        }
    }

    static func text(_ value: Double, kind: PlayerSettingKind) -> String {
        switch kind {
        case .toggle:
            return value >= 0.5 ? "on" : "off"
        case .slider:
            return String(format: "%.2f", value)
        case let .choice(options):
            let index = Int(value.rounded())
            guard options.indices.contains(index) else { return "\(index)" }
            let option = options[index]
            return option.hasPrefix("$") ? String(option.dropFirst()) : option
        }
    }

    public static func bindingRows(_ bindings: InputBindings) -> [KeyBindingRow] {
        InputBindings.slots.map { slot in
            KeyBindingRow(
                event: slot.event,
                key: bindings.scanCode(for: slot.action).map(DirectInputKeyCodes.fallbackName)
                    ?? "none",
                isOverride: bindings.isRemapped(slot.action)
            )
        }
    }

    /// Keys that fire two actions at once. Gameplay and OpenSky actions are both
    /// live while walking, so they share one key space.
    public static func conflicts(_ bindings: InputBindings) -> [String] {
        let live = InputBindings.slots.filter { $0.context != .menu }
        var byKey: [UInt32: [String]] = [:]
        for slot in live {
            guard let code = bindings.scanCode(for: slot.action) else { continue }
            byKey[code, default: []].append(slot.event)
        }
        return byKey.filter { $0.value.count > 1 }.sorted { $0.key < $1.key }.map {
            "\(DirectInputKeyCodes.fallbackName($0.key)): " + $0.value.joined(separator: ", ")
        }
    }
}

extension PlayerSettingsCoordinator {
    /// Puts every setting of one group back to its default.
    public func resetGroup(_ group: PlayerSettingGroup) {
        for definition in store.catalog.definitions(in: group) {
            store.set(definition.id, to: definition.defaultValue)
        }
    }
}
