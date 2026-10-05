// Archery checks on the real install that the synthetic suites cannot make:
// the PROJ `gravity` census shows the arrow band is a multiplier, the vanilla
// iron arrow's drop at a fixed distance is pinned, and every census-named
// archery event resolves on the vanilla player graph. The report in `.logs/`
// holds counts, editor IDs, and numbers only.

import Foundation
@testable import OpenSkyBehavior
@testable import OpenSkyCombat
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyWorld
import simd
import Testing

struct ProjectileRealDataTests {
    /// The distance the drop is reported at. A round number well inside
    /// `fVisibleNavmeshMoveDist`, so it is a shot that could actually be taken.
    private static let dropDistance: Float = 1000

    /// The measurement that settles what PROJ `gravity` means, plus the
    /// vanilla iron arrow's own numbers through the flight model. Writes the
    /// whole report to gitignored `.logs/`.
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func censusesProjectileFlightFields() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let items = ItemDefinitionStore(file: file)
        #expect(!items.projectiles.isEmpty, "this load order carries no PROJ records")

        let arrows = items.projectiles.values.filter { $0.kind == .arrow }
        #expect(!arrows.isEmpty, "this load order carries no arrow-type PROJ records")

        // The finding, as an assertion rather than as prose: over the arrow
        // band the member is bounded by one while `speed` runs to the
        // thousands, which is a dimensionless scale and not an acceleration in
        // units per second squared. If this ever goes red, the reading in
        // `Projectile.swift` and docs/engine/archery.md has to be revisited
        // before the flight model is trusted again.
        let gravities = arrows.map(\.gravityFactor)
        #expect(gravities.allSatisfy { $0 >= 0 && $0 <= 1 })
        #expect(gravities.contains { $0 > 0 })
        #expect(arrows.map(\.speed).max() ?? 0 >= 1000)

        var report = ["OpenSky projectile census — \(items.projectiles.count) PROJ records"]
        for kind in Projectile.Kind.allCases {
            let matching = items.projectiles.values.filter { $0.kind == kind }
            guard !matching.isEmpty else { continue }
            report.append(
                "\(kind): n \(matching.count)"
                    + ", gravity \(Self.describe(matching.map(\.gravityFactor)))"
                    + ", speed \(Self.describe(matching.map(\.speed)))"
            )
        }
        report += try Self.arrowRows(items: items)
        try Self.write(report.joined(separator: "\n") + "\n")
    }

    /// The vanilla iron arrow, end to end: decode its AMMO, follow the PROJ
    /// link, and fly the result. The drop at a fixed distance is the number the
    /// issue's acceptance asks to be pinned.
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func theVanillaIronArrowDropsWhereTheFlightModelSays() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let items = ItemDefinitionStore(file: file)
        let arrow = try #require(
            items.ammunition.values.first { $0.fields.editorID == "IronArrow" },
            "this load order carries no IronArrow"
        )
        let shot = try #require(
            items.archeryAmmunition(arrow.formID),
            "IronArrow names no flyable PROJ"
        )

        // Observed on the local install 2026-08-07: `ArrowIronProjectile`
        // carries speed 3600, gravity 0.350 and range 60000. These are pinned
        // rather than described so a load order that changes them is visible
        // rather than silently producing a different trajectory.
        #expect(shot.profile.speed == 3600)
        #expect(shot.profile.gravityFactor == 0.35)
        #expect(shot.profile.range == 60000)
        #expect(shot.damage == 8)

        // Analytic drop at 1,000 units of level flight: t = 1000/3600 =
        // 0.27778 s, a = 1400 * 0.35 = 490 units/s^2, drop = 0.5 * 490 * t^2 =
        // 18.90 units.
        let analytic = try #require(
            ProjectileFlight.drop(
                of: shot.profile,
                atHorizontalDistance: Self.dropDistance,
                launchDirection: SIMD3(1, 0, 0)
            )
        )
        #expect(abs(analytic - 18.90) < 0.05)

        // The same curve integrated at the runtime's fixed step, as the app does.
        // An arrow moves 30 units per substep and overshoots 1,000, so compare
        // with the closed form at the x where the loop stopped.
        var state = ProjectileFlight.launch(
            from: SIMD3(), along: SIMD3(1, 0, 0), profile: shot.profile
        )
        while state.position.x < Self.dropDistance {
            state = ProjectileFlight.step(
                state, profile: shot.profile, dt: WalkController.fixedTimeStep
            )
        }
        let atStop = try #require(
            ProjectileFlight.drop(
                of: shot.profile,
                atHorizontalDistance: state.position.x,
                launchDirection: SIMD3(1, 0, 0)
            )
        )
        #expect(abs(-state.position.z - atStop) < 0.01)
        // The overshoot is bounded by one substep of travel, so the integrated
        // drop still lands within a couple of units of the pinned figure.
        #expect(abs(-state.position.z - analytic) < 2)
    }

    /// Every archery name has to resolve on the vanilla player graph — the one
    /// that fails loudly if a constant was mistyped or a census reading was
    /// wrong.
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func vanillaGraphAcceptsTheCensusNamedArcheryEvents() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let bridge = try Self.bridge(root: root)

        for name in ArcheryGraphNames.raisedEvents + ArcheryGraphNames.observedEvents {
            bridge.raise(name)
        }
        for name in ArcheryGraphNames.variables {
            bridge.write(.bool(false), to: name)
        }

        #expect(
            bridge.status.missingEvents.isEmpty,
            "the vanilla graph declares no home for \(bridge.status.missingEvents)"
        )
        #expect(
            bridge.status.missingVariables.isEmpty,
            "the vanilla graph declares no home for \(bridge.status.missingVariables)"
        )
    }

    // MARK: - Helpers

    private static func describe(_ values: [Float]) -> String {
        let finite = values.filter(\.isFinite).sorted()
        guard let low = finite.first, let high = finite.last else { return "none" }
        let mean = finite.reduce(0, +) / Float(finite.count)
        return String(format: "min %.3f max %.3f mean %.3f", low, high, mean)
    }

    /// One row per AMMO that names a flyable PROJ, with the drop each reading
    /// of `gravity` predicts. The second column is the rejected reading, kept
    /// in the report so the difference is visible rather than described.
    private static func arrowRows(items: ItemDefinitionStore) throws -> [String] {
        items.ammunition.values
            .sorted { $0.formID.rawValue < $1.formID.rawValue }
            .compactMap { ammo in
                guard let shot = items.archeryAmmunition(ammo.formID) else { return nil }
                let multiplier = ProjectileFlight.drop(
                    of: shot.profile,
                    atHorizontalDistance: dropDistance,
                    launchDirection: SIMD3(1, 0, 0)
                ) ?? 0
                let acceleration = 0.5 * shot.profile.gravityFactor
                    * powf(dropDistance / max(shot.profile.speed, 1), 2)
                return String(
                    format: """
                    %@: damage %.0f, speed %.0f, gravity %.3f, range %.0f, \
                    drop at %.0f = %.2f as multiplier / %.4f as acceleration
                    """,
                    ammo.fields.editorID ?? ammo.formID.description,
                    shot.damage,
                    shot.profile.speed,
                    shot.profile.gravityFactor,
                    shot.profile.range,
                    dropDistance,
                    multiplier,
                    acceleration
                )
            }
    }

    /// The vanilla third-person player graph on a bridge, exactly as item 14.6
    /// attaches it and exactly as `MeleeCombatRealDataTests` builds it. The
    /// reference source matters: `bowDrawStart` and its siblings live in
    /// `1hm_behavior.hkx`, and a graph built without one reaches none of them.
    private static func bridge(root: GameDataRoot) throws -> LocomotionBridge {
        let graph = try PlayerBehaviorGraph.load(
            fileSystem: VirtualFileSystem(root: root)
        ).instance
        let bridge = LocomotionBridge(
            configuration: PlayerMovementConfiguration.resolve(
                store: GameSettingLoader.load(root: root),
                movementTypes: MovementTypeLoader.load(root: root)
            ),
            graph: graph
        )
        graph.activate()
        return bridge
    }

    private static func write(_ report: String) throws {
        let directory = try RepositoryLogs.directory()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        try report.write(
            to: directory.appending(path: "projectile-census.log"),
            atomically: true,
            encoding: .utf8
        )
    }
}
