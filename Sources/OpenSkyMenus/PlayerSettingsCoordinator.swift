// Connects the settings store to the systems that read each value. The store
// owns every value; this pushes a value to its system when it changes, and once
// when a world attaches. See docs/engine/settings.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyGameData

/// What the settings change in the running game. The app answers it.
public protocol PlayerSettingsWorld: AnyObject {
    func applyMasterVolume(_ volume: Float)
    func applyCategoryVolume(_ volume: Float, soundCategoryEditorID: String)
    func applyLook(sensitivity: Float, inverted: Bool)
    func applyHUD(_ hud: PlayerHUDSettings)
    func applyDifficulty(index: Int)
    func applyBindings(_ bindings: InputBindings)
}

nonisolated public struct PlayerHUDSettings: Equatable, Sendable {
    public var crosshair: Bool
    public var compass: Bool
    public var floatingMarkers: Bool
    public var opacity: Float

    public init(crosshair: Bool, compass: Bool, floatingMarkers: Bool, opacity: Float) {
        self.crosshair = crosshair
        self.compass = compass
        self.floatingMarkers = floatingMarkers
        self.opacity = opacity
    }
}

public final class PlayerSettingsCoordinator {
    public let store: PlayerSettingsStore
    private weak var world: PlayerSettingsWorld?
    /// How many times each system was told a value, for the readout.
    public private(set) var applyCount = 0
    /// The install's keys plus the player's remaps.
    public private(set) var bindings = InputBindings()
    private var controlMap: ControlMapFile?

    public init(store: PlayerSettingsStore) {
        self.store = store
        bindings.restore(store.model.keyBindings)
        store.observe { [weak self] id in
            self?.apply(id)
        }
    }

    /// The install's controlmap.txt; nil keeps the built-in vanilla keys.
    public func loadControlMap(_ file: ControlMapFile?) {
        controlMap = file
        rebuildBindings()
    }

    @discardableResult
    public func rebind(_ action: GameInputAction, to scanCode: UInt32) -> InputRebindResult {
        var next = bindings
        let result = next.rebind(action, to: scanCode)
        store.replaceKeyBindings(next.overrides.mapValues(Int.init))
        return result
    }

    public func resetBindings() {
        store.replaceKeyBindings([:])
    }

    private func rebuildBindings() {
        var next = InputBindings(controlMap: controlMap)
        next.restore(store.model.keyBindings)
        bindings = next
        world?.applyBindings(bindings)
    }

    public func attach(world: PlayerSettingsWorld) {
        self.world = world
        applyAll()
    }

    /// Look sensitivity 0.5 is OpenSky's own look speed, 1 doubles it.
    public static func lookMultiplier(_ slider: Double) -> Float {
        Float(max(0.05, slider * 2))
    }

    public func applyAll() {
        for id in [
            PlayerSettingID.masterVolume, .lookSensitivity, .crosshair, .difficulty,
            .keyBindingsChanged
        ] {
            apply(id)
        }
        for (editorID, _) in PlayerSettingsCatalog.audioCategoryEditorIDs {
            apply(.categoryVolume(editorID))
        }
    }

    public func apply(_ id: PlayerSettingID) {
        // The bindings are this coordinator's own state, so they rebuild with no world too.
        if id == .keyBindingsChanged {
            rebuildBindings()
        }
        guard let world else { return }
        applyCount += 1
        switch id {
        case .masterVolume:
            world.applyMasterVolume(Float(store.value(.masterVolume)))
        case .lookSensitivity, .invertLook:
            world.applyLook(
                sensitivity: Self.lookMultiplier(store.value(.lookSensitivity)),
                inverted: store.bool(.invertLook)
            )
        case .crosshair, .compass, .floatingMarkers, .hudOpacity:
            world.applyHUD(hud)
        case .difficulty:
            world.applyDifficulty(index: Int(store.value(.difficulty)))
        case .keyBindingsChanged:
            break
        default:
            applyCategory(id, world: world)
        }
    }

    public var hud: PlayerHUDSettings {
        PlayerHUDSettings(
            crosshair: store.bool(.crosshair), compass: store.bool(.compass),
            floatingMarkers: store.bool(.floatingMarkers),
            opacity: Float(store.value(.hudOpacity))
        )
    }

    private func applyCategory(_ id: PlayerSettingID, world: PlayerSettingsWorld) {
        for (editorID, _) in PlayerSettingsCatalog.audioCategoryEditorIDs
            where id == .categoryVolume(editorID)
        {
            world.applyCategoryVolume(Float(store.value(id)), soundCategoryEditorID: editorID)
        }
    }
}
