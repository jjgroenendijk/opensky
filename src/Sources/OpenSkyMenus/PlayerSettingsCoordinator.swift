// Connects the settings store to the systems that read each value. The store
// owns every value; this pushes a value to its system when it changes, and once
// when a world attaches. See docs/engine/settings.md.

import Foundation
public import OpenSkyFormatsCore
public import OpenSkyGameData
import OpenSkyMenusInterface

/// What the settings change in the running game. The app answers it.
public protocol PlayerSettingsWorld: AnyObject {
    func applyAudioEnabled(_ enabled: Bool)
    func applyMasterVolume(_ volume: Float)
    func applyCategoryVolume(_ volume: Float, soundCategoryEditorID: String)
    func applyLook(sensitivity: Float, inverted: Bool)
    func applyHUD(_ hud: PlayerHUDSettings)
    func applyDifficulty(index: Int)
    func applyBindings(_ bindings: InputBindings)
}

public final class PlayerSettingsCoordinator {
    public let store: PlayerSettingsStore
    private weak let world: any PlayerSettingsWorld?
    /// How many times each system was told a value, for the readout.
    public private(set) var applyCount = 0
    /// The install's keys plus the player's remaps.
    public private(set) var bindings = InputBindings()
    private var controlMap: ControlMapFile?
    /// Reads the install's key names on first use.
    private let keyNamesLoader: () -> KeyboardNameTable?
    private lazy var keyNames = keyNamesLoader()

    /// Call `applyAll()` once the world can take the settings.
    public init(
        store: PlayerSettingsStore,
        world: any PlayerSettingsWorld? = nil,
        keyNamesLoader: @escaping () -> KeyboardNameTable? = { nil }
    ) {
        self.store = store
        self.world = world
        self.keyNamesLoader = keyNamesLoader
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
    func rebind(_ action: GameInputAction, to scanCode: UInt32) -> InputRebindResult {
        var next = bindings
        let result = next.rebind(action, to: scanCode)
        store.replaceKeyBindings(next.savedBindings)
        return result
    }

    @discardableResult
    func rebindGamepad(_ action: GameInputAction, to code: UInt32) -> InputRebindResult {
        var next = bindings
        let result = next.rebindGamepad(action, to: code)
        store.replaceKeyBindings(next.savedBindings)
        return result
    }

    /// The install's name for a key, such as `L-Ctrl`, or a built-in one. A mouse
    /// button is `Mouse1` to `Mouse8`, the symbols of the movies' mouse art.
    public func keyName(_ scanCode: UInt32) -> String {
        InputCode.mouseName(scanCode) ?? keyNames?.name(scanCode)
            ?? DirectInputKeyCodes.fallbackName(scanCode)
    }

    /// The art name of the input bound to a controlmap user event, such as "E" for
    /// "Activate", or "360_A" with a gamepad. An event the player cannot remap, such as
    /// "Zoom In", answers with its first input in the control map.
    public func buttonName(forUserEvent event: String, gamepad: Bool) -> String? {
        let slot = InputBindings.slots.first { $0.event == event }
        if gamepad {
            let code = slot.flatMap { bindings.gamepadCodes(for: $0.action).first }
                ?? controlMapCode(of: event, device: .gamepad)
            return code.flatMap { GamepadButton(controlMapCode: $0)?.artName }
        }
        if let slot, let scanCode = bindings.scanCode(for: slot.action) {
            return keyName(scanCode)
        }
        if let code = controlMapCode(of: event, device: .keyboard) {
            return keyName(code)
        }
        return controlMapCode(of: event, device: .mouse).map { keyName(InputCode.mouse(Int($0))) }
    }

    /// The keyboard and mouse art name, for callers that never show gamepad art.
    public func buttonName(forUserEvent event: String) -> String? {
        buttonName(forUserEvent: event, gamepad: false)
    }

    private func controlMapCode(of event: String, device: ControlDevice) -> UInt32? {
        guard let controlMap else { return nil }
        for context in controlMap.contexts.indices {
            if let code = controlMap.codes(of: event, in: context, device: device).first {
                return code
            }
        }
        return nil
    }

    func resetBindings() {
        store.replaceKeyBindings([:])
    }

    private func rebuildBindings() {
        var next = InputBindings(controlMap: controlMap)
        next.restore(store.model.keyBindings)
        bindings = next
        world?.applyBindings(bindings)
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
        case .audioEnabled:
            world.applyAudioEnabled(store.bool(.audioEnabled))
        case .masterVolume:
            world.applyMasterVolume(Float(store.value(.masterVolume)))
        case .lookSensitivity, .invertLook:
            world.applyLook(
                sensitivity: Self.lookMultiplier(store.value(.lookSensitivity)),
                inverted: store.bool(.invertLook)
            )
        case .crosshair, .compass, .floatingMarkers, .hudOpacity, .dialogueSubtitles,
             .generalSubtitles:
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
            opacity: Float(store.value(.hudOpacity)),
            subtitles: SubtitleSettings(
                dialogue: store.bool(.dialogueSubtitles), general: store.bool(.generalSubtitles)
            )
        )
    }

    private func applyCategory(_ id: PlayerSettingID, world: any PlayerSettingsWorld) {
        for (editorID, _) in PlayerSettingsCatalog.audioCategoryEditorIDs
            where id == .categoryVolume(editorID)
        {
            world.applyCategoryVolume(Float(store.value(id)), soundCategoryEditorID: editorID)
        }
    }
}
