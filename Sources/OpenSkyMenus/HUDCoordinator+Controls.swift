// The HUD coordinator answers the HUD panel seam, in the panel's names.

extension HUDCoordinator: HUDControlProviding {
    public var hudLayerEnabled: Bool {
        get { settings.layerEnabled }
        set { update { $0.layerEnabled = newValue } }
    }

    public var hudCrosshairEnabled: Bool {
        get { settings.crosshairEnabled }
        set { update { $0.crosshairEnabled = newValue } }
    }

    public var hudMetersEnabled: Bool {
        get { settings.metersEnabled }
        set { update { $0.metersEnabled = newValue } }
    }

    public var hudCompassEnabled: Bool {
        get { settings.compassEnabled }
        set { update { $0.compassEnabled = newValue } }
    }

    public var hudMarkersEnabled: Bool {
        get { settings.markersEnabled }
        set { update { $0.markersEnabled = newValue } }
    }

    public var hudPromptEnabled: Bool {
        get { settings.promptEnabled }
        set { update { $0.promptEnabled = newValue } }
    }

    public var hudPlaceholderTextEnabled: Bool {
        get { settings.placeholderTextEnabled }
        set { update { $0.placeholderTextEnabled = newValue } }
    }

    public var hudScale: Float {
        get { settings.scale }
        set { update { $0.scale = newValue } }
    }

    public var hudControlSnapshot: HUDControlSnapshot {
        controlSnapshot
    }
}
