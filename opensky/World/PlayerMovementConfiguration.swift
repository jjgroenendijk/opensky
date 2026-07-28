// Immutable controller tuning resolved once at setup. The controller never
// reaches back into game data, which keeps fixed-step simulation deterministic.

nonisolated struct MovementSetting: Equatable {
    let value: Float
    let source: String
}

nonisolated struct PlayerMovementConfiguration: Equatable {
    let walkSpeed: MovementSetting
    let runSpeed: MovementSetting
    let stepHeight: MovementSetting

    /// Historic explicit values for synthetic scenes, tests, and benchmarks.
    static let synthetic = PlayerMovementConfiguration(
        walkSpeed: MovementSetting(value: 180, source: "OpenSky synthetic"),
        runSpeed: MovementSetting(value: 360, source: "OpenSky synthetic"),
        stepHeight: MovementSetting(value: 32, source: "OpenSky synthetic")
    )

    static func resolve(store: GameSettingStore) -> PlayerMovementConfiguration {
        PlayerMovementConfiguration(
            walkSpeed: float(
                editorID: "fMoveCharWalkBase",
                store: store,
                fallback: 100,
                fallbackSource: "engine default"
            ),
            runSpeed: float(
                editorID: "fMoveCharRunBase",
                store: store,
                fallback: 370,
                fallbackSource: "engine default"
            ),
            stepHeight: MovementSetting(
                value: 32,
                source: "OpenSky fallback (no confirmed Skyrim SE GMST)"
            )
        )
    }

    private static func float(
        editorID: String,
        store: GameSettingStore,
        fallback: Float,
        fallbackSource: String
    ) -> MovementSetting {
        guard
            let resolved = store.setting(editorID: editorID),
            case let .float(value) = resolved.setting.value,
            value.isFinite,
            value > 0
        else {
            return MovementSetting(value: fallback, source: fallbackSource)
        }
        return MovementSetting(value: value, source: resolved.sourcePlugin)
    }
}
