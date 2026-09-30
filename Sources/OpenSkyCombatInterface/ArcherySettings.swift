// The game settings a bow shot reads, resolved once at setup so a fixed step never
// reads game data mid-step. No vanilla plugin authors them, so each reports the
// UESP default unless a mod adds the GMST.
// Documented in docs/engine/projectiles.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics

nonisolated public struct ArcherySettings: Equatable, Sendable {
    /// `f1PArrowTiltUpAngle` — degrees the aim ray is tilted up by in first
    /// person. UESP gives the default as 2.
    public let firstPersonTiltUpAngle: MovementSetting
    /// `f3PArrowTiltUpAngle` — the same in third person. UESP gives 2.5.
    public let thirdPersonTiltUpAngle: MovementSetting
    /// `fVisibleNavmeshMoveDist` — the distance past which a shot stops being
    /// able to hit anything, world units. UESP gives 4096 and notes the
    /// Unofficial Patch triples it, which is exactly the kind of load-order
    /// difference a resolved-with-source setting exists to make visible.
    public let visibleMoveDistance: MovementSetting

    /// Values for synthetic scenes and tests: the documented defaults, stated
    /// explicitly so a test never depends on an install being present.
    public static let synthetic = ArcherySettings(
        firstPersonTiltUpAngle: MovementSetting(value: 2, source: "OpenSky synthetic"),
        thirdPersonTiltUpAngle: MovementSetting(value: 2.5, source: "OpenSky synthetic"),
        visibleMoveDistance: MovementSetting(value: 4096, source: "OpenSky synthetic")
    )

    /// The tilt for one perspective, in degrees.
    public func tiltUpAngle(firstPerson: Bool) -> MovementSetting {
        firstPerson ? firstPersonTiltUpAngle : thirdPersonTiltUpAngle
    }

    /// Reads every setting out of `store`, falling back to the UESP-documented
    /// default and saying so when the load order carries none.
    public static func resolve(store: GameSettingStore) -> ArcherySettings {
        ArcherySettings(
            firstPersonTiltUpAngle: float("f1PArrowTiltUpAngle", store: store, fallback: 2),
            thirdPersonTiltUpAngle: float("f3PArrowTiltUpAngle", store: store, fallback: 2.5),
            visibleMoveDistance: float("fVisibleNavmeshMoveDist", store: store, fallback: 4096)
        )
    }

    /// Every setting paired with its editor ID, for the CLI report and the
    /// panel readout.
    public var report: [(editorID: String, setting: MovementSetting)] {
        [
            ("f1PArrowTiltUpAngle", firstPersonTiltUpAngle),
            ("f3PArrowTiltUpAngle", thirdPersonTiltUpAngle),
            ("fVisibleNavmeshMoveDist", visibleMoveDistance)
        ]
    }

    private static func float(
        _ editorID: String,
        store: GameSettingStore,
        fallback: Float
    ) -> MovementSetting {
        guard
            let resolved = store.setting(editorID: editorID),
            case let .float(value) = resolved.setting.value,
            value.isFinite
        else {
            return MovementSetting(value: fallback, source: "UESP-documented default")
        }
        return MovementSetting(value: value, source: resolved.sourcePlugin)
    }
}
