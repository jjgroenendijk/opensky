// Immutable controller tuning resolved once at setup. The controller never
// reaches back into game data, which keeps fixed-step simulation deterministic.
//
// Every value carries the name of where it came from, so a readout can say
// "this is Skyrim.esm's number" or "this is an OpenSky fallback" rather than
// presenting both as the same kind of fact. Walk and run come from GMSTs; the
// sneak, sprint, and swim gaits have no GMST and come from the MOVT records the
// player's gaits are authored in (docs/formats/records.md).

nonisolated struct MovementSetting: Equatable {
    let value: Float
    let source: String
}

nonisolated struct PlayerMovementConfiguration: Equatable {
    let walkSpeed: MovementSetting
    let runSpeed: MovementSetting
    /// Sprint gait, `NPC_Sprinting_MT` forward run in vanilla (issue #188).
    let sprintSpeed: MovementSetting
    /// Sneak gait, `NPC_Sneaking_MT` forward run.
    let sneakSpeed: MovementSetting
    /// Swim gait, `NPC_Swimming_MT` forward run.
    let swimSpeed: MovementSetting
    let stepHeight: MovementSetting
    /// Upward velocity a jump takes off at, derived from the jump height
    /// `fJumpHeightMin` states and the controller's own gravity.
    let jumpTakeoffSpeed: MovementSetting

    /// The gaits added in item 14.5 default to ratios of the two that came
    /// before them, so a caller that only knows about walk and run — a
    /// synthetic scene, a benchmark — still builds a complete configuration.
    /// Nothing resolving from real data uses these defaults; `resolve` passes
    /// every field.
    init(
        walkSpeed: MovementSetting,
        runSpeed: MovementSetting,
        stepHeight: MovementSetting,
        sprintSpeed: MovementSetting? = nil,
        sneakSpeed: MovementSetting? = nil,
        swimSpeed: MovementSetting? = nil,
        jumpTakeoffSpeed: MovementSetting? = nil
    ) {
        self.walkSpeed = walkSpeed
        self.runSpeed = runSpeed
        self.stepHeight = stepHeight
        self.sprintSpeed = sprintSpeed
            ?? MovementSetting(value: runSpeed.value * 1.35, source: "derived from run speed")
        self.sneakSpeed = sneakSpeed
            ?? MovementSetting(value: walkSpeed.value * 0.5, source: "derived from walk speed")
        self.swimSpeed = swimSpeed
            ?? MovementSetting(value: walkSpeed.value, source: "derived from walk speed")
        self.jumpTakeoffSpeed = jumpTakeoffSpeed
            ?? MovementSetting(
                value: (2 * WalkController.gravity * 76).squareRoot(),
                source: "fJumpHeightMin engine default over gravity"
            )
    }

    /// Historic explicit values for synthetic scenes, tests, and benchmarks.
    static let synthetic = PlayerMovementConfiguration(
        walkSpeed: MovementSetting(value: 180, source: "OpenSky synthetic"),
        runSpeed: MovementSetting(value: 360, source: "OpenSky synthetic"),
        stepHeight: MovementSetting(value: 32, source: "OpenSky synthetic"),
        sprintSpeed: MovementSetting(value: 540, source: "OpenSky synthetic"),
        sneakSpeed: MovementSetting(value: 90, source: "OpenSky synthetic"),
        swimSpeed: MovementSetting(value: 180, source: "OpenSky synthetic"),
        jumpTakeoffSpeed: MovementSetting(value: 460, source: "OpenSky synthetic")
    )

    static func resolve(
        store: GameSettingStore,
        movementTypes: MovementTypeStore = .empty
    ) -> PlayerMovementConfiguration {
        let run = float(
            editorID: "fMoveCharRunBase",
            store: store,
            fallback: 370,
            fallbackSource: "engine default"
        )
        return PlayerMovementConfiguration(
            walkSpeed: float(
                editorID: "fMoveCharWalkBase",
                store: store,
                fallback: 100,
                fallbackSource: "engine default"
            ),
            runSpeed: run,
            stepHeight: MovementSetting(
                value: 32,
                source: "OpenSky fallback (no confirmed Skyrim SE GMST)"
            ),
            sprintSpeed: gait(
                editorID: MovementTypeStore.PlayerGait.sprinting,
                slot: .run,
                store: movementTypes,
                fallback: run.value * 1.35,
                fallbackSource: "OpenSky fallback (no NPC_Sprinting_MT)"
            ),
            // Sneak and swim take the walk slot: both are the slow gait of
            // their movement type, and OpenSky binds no separate "run while
            // sneaking" key for the fast one to belong to.
            sneakSpeed: gait(
                editorID: MovementTypeStore.PlayerGait.sneaking,
                slot: .walk,
                store: movementTypes,
                fallback: run.value * 0.6,
                fallbackSource: "OpenSky fallback (no NPC_Sneaking_MT)"
            ),
            swimSpeed: gait(
                editorID: MovementTypeStore.PlayerGait.swimming,
                slot: .walk,
                store: movementTypes,
                fallback: run.value,
                fallbackSource: "OpenSky fallback (no NPC_Swimming_MT)"
            ),
            jumpTakeoffSpeed: jumpTakeoff(store: store)
        )
    }

    /// Takeoff speed for the jump height the data states.
    ///
    /// `fJumpHeightMin` is a height in world units (76 in Skyrim.esm), not a
    /// speed, so it converts through the controller's own gravity: reaching
    /// height `h` under constant gravity `g` needs `sqrt(2 g h)`. That keeps
    /// the apex on the authored number instead of on a hand-tuned impulse, and
    /// it stays right if either the GMST or the gravity constant changes.
    private static func jumpTakeoff(store: GameSettingStore) -> MovementSetting {
        let height = float(
            editorID: "fJumpHeightMin",
            store: store,
            fallback: 76,
            fallbackSource: "engine default"
        )
        let speed = (2 * WalkController.gravity * max(height.value, 0)).squareRoot()
        return MovementSetting(
            value: speed.isFinite ? speed : 0,
            source: "fJumpHeightMin \(height.value) [\(height.source)] over gravity"
        )
    }

    /// Which of a movement type's two forward speeds a gait reads.
    private enum GaitSlot: String {
        case walk
        case run
    }

    private static func gait(
        editorID: String,
        slot: GaitSlot,
        store: MovementTypeStore,
        fallback: Float,
        fallbackSource: String
    ) -> MovementSetting {
        let speeds = store.forwardSpeeds(editorID: editorID)
        let value = slot == .walk ? speeds?.walk : speeds?.run
        guard let value, value.isFinite, value > 0 else {
            return MovementSetting(value: fallback, source: fallbackSource)
        }
        return MovementSetting(
            value: value, source: "\(editorID) SPED forward \(slot.rawValue)"
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
