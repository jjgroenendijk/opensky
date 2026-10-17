// Typed reads of one game setting. A settings struct starts from its vanilla values
// and lays each setting the load order defines over one field, so a missing or
// wrongly typed record keeps the vanilla value. See docs/formats/gmst.md.

import Foundation
import OpenSkyFormatsESM

nonisolated extension GameSettingStore {
    /// A float or integer setting as a finite `Float`.
    public func number(_ editorID: String) -> Float? {
        switch setting(editorID: editorID)?.setting.value {
        case let .float(value)? where value.isFinite: value
        case let .integer(value)?: Float(value)
        default: nil
        }
    }

    /// An integer setting, or a float one with no fraction.
    public func integer(_ editorID: String) -> Int? {
        switch setting(editorID: editorID)?.setting.value {
        case let .integer(value)?: Int(value)
        case let .float(value)? where value.isFinite && value.rounded() == value: Int(value)
        default: nil
        }
    }

    public func boolean(_ editorID: String) -> Bool? {
        switch setting(editorID: editorID)?.setting.value {
        case let .boolean(value)?: value
        case let .integer(value)?: value != 0
        default: nil
        }
    }

    /// A string setting, still to be resolved through the plugin's string table.
    public func text(_ editorID: String) -> ResolvedGameText? {
        guard
            let resolved = setting(editorID: editorID),
            case let .string(text) = resolved.setting.value
        else { return nil }
        return ResolvedGameText(text: text, sourcePlugin: resolved.sourcePlugin)
    }

    public func read<Settings>(
        _ editorID: String, into settings: inout Settings,
        _ keyPath: WritableKeyPath<Settings, Float>
    ) {
        if let value = number(editorID) {
            settings[keyPath: keyPath] = value
        }
    }

    public func read<Settings>(
        _ editorID: String, into settings: inout Settings,
        _ keyPath: WritableKeyPath<Settings, Int>
    ) {
        if let value = integer(editorID) {
            settings[keyPath: keyPath] = value
        }
    }

    /// A string setting, resolved through `text`; nil from `text` keeps the field.
    public func read<Settings>(
        _ editorID: String, into settings: inout Settings,
        _ keyPath: WritableKeyPath<Settings, String>, text: GameTextResolver
    ) {
        if let value = self.text(editorID).flatMap({ text($0) }) {
            settings[keyPath: keyPath] = value
        }
    }

    public func read<Settings>(
        _ editorID: String, into settings: inout Settings,
        _ keyPath: WritableKeyPath<Settings, Bool>
    ) {
        if let value = boolean(editorID) {
            settings[keyPath: keyPath] = value
        }
    }
}

/// A string setting and the plugin whose string table holds it.
nonisolated public struct ResolvedGameText: Equatable, Sendable {
    public let text: LString
    public let sourcePlugin: String

    public init(text: LString, sourcePlugin: String) {
        self.text = text
        self.sourcePlugin = sourcePlugin
    }
}

/// Resolves a string setting through the string table of its own plugin.
public typealias GameTextResolver = (ResolvedGameText) -> String?
