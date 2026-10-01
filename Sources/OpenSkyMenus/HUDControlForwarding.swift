// Lets the app's provider object stand in for its `HUDCoordinator`, so the
// panel registry keeps one provider value without a forward per member.

public protocol HUDControlForwarding: HUDControlProviding {
    var hud: HUDCoordinator { get }
}

extension HUDControlForwarding {
    public var hudLayerEnabled: Bool {
        get { hud.settings.layerEnabled }
        set { hud.update { $0.layerEnabled = newValue } }
    }

    public var hudCrosshairEnabled: Bool {
        get { hud.settings.crosshairEnabled }
        set { hud.update { $0.crosshairEnabled = newValue } }
    }

    public var hudMetersEnabled: Bool {
        get { hud.settings.metersEnabled }
        set { hud.update { $0.metersEnabled = newValue } }
    }

    public var hudCompassEnabled: Bool {
        get { hud.settings.compassEnabled }
        set { hud.update { $0.compassEnabled = newValue } }
    }

    public var hudMarkersEnabled: Bool {
        get { hud.settings.markersEnabled }
        set { hud.update { $0.markersEnabled = newValue } }
    }

    public var hudPromptEnabled: Bool {
        get { hud.settings.promptEnabled }
        set { hud.update { $0.promptEnabled = newValue } }
    }

    public var hudPlaceholderTextEnabled: Bool {
        get { hud.settings.placeholderTextEnabled }
        set { hud.update { $0.placeholderTextEnabled = newValue } }
    }

    public var hudScale: Float {
        get { hud.settings.scale }
        set { hud.update { $0.scale = newValue } }
    }

    public var hudControlSnapshot: HUDControlSnapshot {
        hud.controlSnapshot
    }
}
