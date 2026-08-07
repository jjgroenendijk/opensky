// The GMSTs a bow shot resolves its numbers from (issue #196, roadmap item
// 15.5), in the shape `CombatSettings` and `PlayerMovementConfiguration`
// already established: immutable, resolved once at setup, every value carrying
// the name of where it came from so a readout can say "this is Skyrim.esm's
// number" rather than presenting a fallback as the same kind of fact.
//
// Resolved once rather than looked up per shot for the same reason the combat
// settings are: a fixed-step simulation that reaches back into game data
// mid-step is a simulation whose result depends on when it was asked.
//
// UESP "Skyrim:Archery", section "Range and Trajectory", is the source for all
// three, and it is unusually explicit about what they do:
//
// * "The primary factor affecting your maximum range is the global game
//   setting fVisibleNavmeshMoveDist; past this distance, your arrows will
//   'phase through' targets without doing any damage. The default value is
//   4096 distance units (for reference, a weapon with a reach of '1' has a
//   reach of 141 distance units, by default)." — the parenthesis is the same
//   `fCombatDistance` melee resolves to 141.000 on this install, which is a
//   useful cross-check that the page and the install are talking about the
//   same units.
// * "The primary factor affecting your trajectory is the set of global game
//   settings: f1PArrowTiltUpAngle; default 2. f3PArrowTiltUpAngle; default
//   2.5. ... These set the angle your projectiles fire at from bows ... A
//   value of 0 is initially flat, along the bottom of the targeting reticle.
//   Positive values tilt the projectile up."
//
// So the aim ray is the camera's, tilted up by whichever of the two the
// current perspective names, and the shot is given up on past
// `fVisibleNavmeshMoveDist` even when the PROJ's own `range` is larger — which
// on vanilla arrows it is by a wide margin.
//
// One measurement, because it changes what a reader should expect from the
// readout: **none of the three is a GMST record on this install.** Resolving
// them against the active load order on 2026-08-07 (`openskycli gmst archery`)
// answers with the documented fallback for all three, and neither
// `Skyrim_Default.ini` nor the four quality presets beside it names any of
// them. UESP calls them "global game settings" and they are engine defaults
// rather than data — so the source string every one of them reports is
// "UESP-documented default", and that is the truth rather than a degraded
// answer. The resolution is kept anyway: a mod that *does* add the GMST should
// win, and the readout should say which plugin did it.
//
// The two bolt settings UESP lists beside these (`f1PBoltTiltUpAngle`,
// `f3PBoltTiltUpAngle`) are deliberately not resolved: crossbows are out of
// item 15.5's scope, and a setting nothing reads is a setting that can go stale
// unnoticed.
//
// Documented in docs/engine/archery.md.

import Foundation

nonisolated struct ArcherySettings: Equatable {
    /// `f1PArrowTiltUpAngle` — degrees the aim ray is tilted up by in first
    /// person. UESP gives the default as 2.
    let firstPersonTiltUpAngle: MovementSetting
    /// `f3PArrowTiltUpAngle` — the same in third person. UESP gives 2.5.
    let thirdPersonTiltUpAngle: MovementSetting
    /// `fVisibleNavmeshMoveDist` — the distance past which a shot stops being
    /// able to hit anything, world units. UESP gives 4096 and notes the
    /// Unofficial Patch triples it, which is exactly the kind of load-order
    /// difference a resolved-with-source setting exists to make visible.
    let visibleMoveDistance: MovementSetting

    /// Values for synthetic scenes and tests: the documented defaults, stated
    /// explicitly so a test never depends on an install being present.
    static let synthetic = ArcherySettings(
        firstPersonTiltUpAngle: MovementSetting(value: 2, source: "OpenSky synthetic"),
        thirdPersonTiltUpAngle: MovementSetting(value: 2.5, source: "OpenSky synthetic"),
        visibleMoveDistance: MovementSetting(value: 4096, source: "OpenSky synthetic")
    )

    /// The tilt for one perspective, in degrees.
    func tiltUpAngle(firstPerson: Bool) -> MovementSetting {
        firstPerson ? firstPersonTiltUpAngle : thirdPersonTiltUpAngle
    }

    /// Reads every setting out of `store`, falling back to the UESP-documented
    /// default and saying so when the load order carries none.
    static func resolve(store: GameSettingStore) -> ArcherySettings {
        ArcherySettings(
            firstPersonTiltUpAngle: float("f1PArrowTiltUpAngle", store: store, fallback: 2),
            thirdPersonTiltUpAngle: float("f3PArrowTiltUpAngle", store: store, fallback: 2.5),
            visibleMoveDistance: float("fVisibleNavmeshMoveDist", store: store, fallback: 4096)
        )
    }

    /// Every setting paired with its editor ID, for the CLI report and the
    /// panel readout.
    var report: [(editorID: String, setting: MovementSetting)] {
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
