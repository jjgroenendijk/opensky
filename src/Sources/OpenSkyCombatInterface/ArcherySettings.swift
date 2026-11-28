// The game settings a bow shot reads, resolved once at setup so a fixed step never
// reads game data mid-step. No vanilla plugin authors them, so each reports the
// UESP default unless a mod adds the GMST.
// Documented in docs/engine/projectiles.md.

import Foundation
import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyPhysics

nonisolated public struct ArcherySettings: Equatable, Sendable {
    /// `f1PArrowTiltUpAngle` — degrees the aim ray is tilted up by in first
    /// person. UESP gives the default as 2.
    public let firstPersonTiltUpAngle: MovementSetting
    /// `f3PArrowTiltUpAngle` — the same in third person. UESP gives 2.5.
    public let thirdPersonTiltUpAngle: MovementSetting
    /// `f1PBoltTiltUpAngle` and `f3PBoltTiltUpAngle`: the same for a crossbow bolt. The game
    /// program defaults them to 1 and 2.5.
    public var firstPersonBoltTiltUpAngle = MovementSetting(value: 1, source: "OpenSky synthetic")
    public var thirdPersonBoltTiltUpAngle = MovementSetting(
        value: 2.5, source: "OpenSky synthetic"
    )
    /// `fVisibleNavmeshMoveDist` — the distance past which a shot stops being
    /// able to hit anything, world units. UESP gives 4096 and notes the
    /// Unofficial Patch triples it, which is exactly the kind of load-order
    /// difference a resolved-with-source setting exists to make visible.
    public let visibleMoveDistance: MovementSetting
    /// `fBowZoomStaminaDrainMult`: stamina a second while zoomed with a bow, before perks.
    /// The install sets 0.
    public var bowZoomStaminaDrain: Float = 0
    /// `fBowNPCSpreadAngle`: the widest an unskilled NPC's arrow leaves its aim line, in
    /// degrees. The program default is 5; `Skyrim.esm` sets 4.
    public var npcSpreadDegrees: Float = 5
    /// `fCombatAimProjectileGroundMinRadius`: past this blast radius an NPC aims at the
    /// target's feet.
    public var groundAimMinimumRadius: Float = 128

    /// Values for synthetic scenes and tests: the documented defaults, stated
    /// explicitly so a test never depends on an install being present.
    public static let synthetic = ArcherySettings(
        firstPersonTiltUpAngle: MovementSetting(value: 2, source: "OpenSky synthetic"),
        thirdPersonTiltUpAngle: MovementSetting(value: 2.5, source: "OpenSky synthetic"),
        visibleMoveDistance: MovementSetting(value: 4096, source: "OpenSky synthetic")
    )

    /// The tilt for one perspective, in degrees.
    public func tiltUpAngle(firstPerson: Bool, bolt: Bool = false) -> MovementSetting {
        if bolt {
            return firstPerson ? firstPersonBoltTiltUpAngle : thirdPersonBoltTiltUpAngle
        }
        return firstPerson ? firstPersonTiltUpAngle : thirdPersonTiltUpAngle
    }

    /// Reads every setting out of `store`, falling back to the UESP-documented
    /// default and saying so when the load order carries none.
    public static func resolve(store: GameSettingStore) -> ArcherySettings {
        var settings = ArcherySettings(
            firstPersonTiltUpAngle: float("f1PArrowTiltUpAngle", store: store, fallback: 2),
            thirdPersonTiltUpAngle: float("f3PArrowTiltUpAngle", store: store, fallback: 2.5),
            visibleMoveDistance: float("fVisibleNavmeshMoveDist", store: store, fallback: 4096)
        )
        settings.firstPersonBoltTiltUpAngle = float("f1PBoltTiltUpAngle", store: store, fallback: 1)
        settings.thirdPersonBoltTiltUpAngle = float(
            "f3PBoltTiltUpAngle",
            store: store,
            fallback: 2.5
        )
        store.read("fBowZoomStaminaDrainMult", into: &settings, \.bowZoomStaminaDrain)
        store.read("fBowNPCSpreadAngle", into: &settings, \.npcSpreadDegrees)
        store.read(
            "fCombatAimProjectileGroundMinRadius", into: &settings, \.groundAimMinimumRadius
        )
        return settings
    }

    /// Whether an NPC aims a shot at the target's feet instead of the middle of its
    /// capsule. The blast is the larger of the explosion radius and the largest spell
    /// area times 22. Example: a spell area of 10 gives 220, past the vanilla 128.
    public func aimsAtFeet(explosionRadius: Float, spellArea: UInt32) -> Bool {
        let radius = max(explosionRadius.isFinite ? explosionRadius : 0, Float(spellArea) * 22)
        return radius > groundAimMinimumRadius
    }

    /// Every setting paired with its editor ID, for the CLI report and the
    /// readout.
    public var report: [(editorID: String, setting: MovementSetting)] {
        [
            ("f1PArrowTiltUpAngle", firstPersonTiltUpAngle),
            ("f3PArrowTiltUpAngle", thirdPersonTiltUpAngle),
            ("f1PBoltTiltUpAngle", firstPersonBoltTiltUpAngle),
            ("f3PBoltTiltUpAngle", thirdPersonBoltTiltUpAngle),
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
