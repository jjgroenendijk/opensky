// The text the system menu's readout and messages show for settings and key bindings.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsMesh
import OpenSkyFormatsSWF
import OpenSkyGameData
import OpenSkyMenusInterface
import OpenSkyProgressionInterface
import OpenSkyRendering
import simd

extension PlayerSettingsCoordinator {
    /// One row per bound slot, then the Reset row.
    var controlsRows: [String] {
        InputBindings.slots.map { slot in
            let key = bindings.scanCode(for: slot.action).map { keyName($0) } ?? "none"
            return "\(slot.event): \(key)"
        } + [ControlsPageModel.resetTitle]
    }

    /// The category titles, or the open category's rows with their values.
    func settingsRows(_ page: SettingsPageModel) -> (rows: [String], selected: Int) {
        guard page.openGroup != nil else {
            return (
                SettingsPageModel.categories.map(\.title),
                SettingsPageModel.categories.firstIndex(of: page.selectedCategory) ?? 0
            )
        }
        let rows = page.rows.map { id in
            let definition = store.catalog.definition(id)
            let value = Self.valueText(store.value(id), definition: definition)
            return "\(definition?.title ?? id.rawValue): \(value)"
        }
        return (rows, page.rowIndex)
    }

    static func valueText(_ value: Double, definition: PlayerSettingDefinition?) -> String {
        switch definition?.kind {
        case .toggle: value >= 0.5 ? "On" : "Off"
        case let .choice(options):
            options.indices.contains(Int(value)) ? options[Int(value)] : "\(Int(value))"
        default: unsafe String(format: "%.2f", value)
        }
    }

    /// Rebinds `action` and says what happened.
    func rebindMessage(_ action: GameInputAction, to scanCode: UInt32) -> String {
        switch rebind(action, to: scanCode) {
        case .bound: "Bound \(action.rawValue)"
        case let .swapped(other): "Bound \(action.rawValue), swapped with \(other.rawValue)"
        case .notRemappable: "\(action.rawValue) cannot be remapped"
        case .unknownKey: "That key cannot be bound"
        }
    }

    /// The master volume, as the audio mix reads it.
    var masterVolume: Float {
        get { Float(store.value(.masterVolume)) }
        set { store.set(.masterVolume, to: Double(newValue)) }
    }

    func binds(_ action: GameInputAction, to scanCode: UInt32) -> Bool {
        bindings.scanCode(for: action) == scanCode
    }
}
