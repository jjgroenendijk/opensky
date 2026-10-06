// Controller tuning, resolved once at setup, so the fixed step never reads game data.
// Each value names its source, so a readout can tell Skyrim.esm data from an OpenSky
// fallback. Walk and run come from GMSTs; sneak, sprint and swim from MOVT records
// (docs/formats/records.md).

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics

nonisolated public struct PlayerMovementConfiguration: Equatable, Sendable {
    public let walkSpeed: MovementSetting
    public let runSpeed: MovementSetting
    /// Sprint gait, `NPC_Sprinting_MT` forward run in vanilla.
    public let sprintSpeed: MovementSetting
    /// Sneak gait, `NPC_Sneaking_MT` forward run.
    public let sneakSpeed: MovementSetting
    /// Swim gait, `NPC_Swimming_MT` forward run.
    public let swimSpeed: MovementSetting
    public let stepHeight: MovementSetting
    /// Upward velocity a jump takes off at, derived from the jump height
    /// `fJumpHeightMin` states and the controller's own gravity.
    public let jumpTakeoffSpeed: MovementSetting
    /// The walk a fast travel trip is timed at, `NPC_Default_MT` forward walk.
    public let travelSpeed: MovementSetting

    /// Sneak, sprint and swim default to ratios of walk and run, so a synthetic scene or
    /// benchmark still builds a full configuration. `resolve` sets every field.
    public init(
        walkSpeed: MovementSetting,
        runSpeed: MovementSetting,
        stepHeight: MovementSetting,
        sprintSpeed: MovementSetting? = nil,
        sneakSpeed: MovementSetting? = nil,
        swimSpeed: MovementSetting? = nil,
        jumpTakeoffSpeed: MovementSetting? = nil,
        travelSpeed: MovementSetting? = nil
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
        self.travelSpeed = travelSpeed
            ?? MovementSetting(value: walkSpeed.value, source: "derived from walk speed")
    }

    /// Historic explicit values for synthetic scenes, tests, and benchmarks.
    public static let synthetic = PlayerMovementConfiguration(
        walkSpeed: MovementSetting(value: 180, source: "OpenSky synthetic"),
        runSpeed: MovementSetting(value: 360, source: "OpenSky synthetic"),
        stepHeight: MovementSetting(value: 32, source: "OpenSky synthetic"),
        sprintSpeed: MovementSetting(value: 540, source: "OpenSky synthetic"),
        sneakSpeed: MovementSetting(value: 90, source: "OpenSky synthetic"),
        swimSpeed: MovementSetting(value: 180, source: "OpenSky synthetic"),
        jumpTakeoffSpeed: MovementSetting(value: 460, source: "OpenSky synthetic")
    )

    public static func resolve(
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
            jumpTakeoffSpeed: jumpTakeoff(store: store),
            travelSpeed: gait(
                editorID: MovementTypeStore.PlayerGait.walking,
                slot: .walk,
                store: movementTypes,
                fallback: 80,
                fallbackSource: "OpenSky fallback (no NPC_Default_MT)"
            )
        )
    }

    /// Takeoff speed for the data's jump height. `fJumpHeightMin` is a height (76 in
    /// Skyrim.esm), so the speed is `sqrt(2 g h)` with the controller's own gravity.
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
