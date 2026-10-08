// `archery`: walks AMMO -> PROJ -> flight. It settles the unit of PROJ
// `gravity`, which no spec states: an acceleration would be in the hundreds, a
// multiplier over world gravity near one. `--census` prints the distribution.

import Foundation
import OpenSkyCLIArguments
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics

enum ArcheryCommand {
    /// Where the per-arrow drop is reported. It is inside
    /// `fVisibleNavmeshMoveDist`, so a real shot can travel it.
    static let dropDistance: Float = 1000

    static func run(context: CLIContext, arguments: ArcheryArguments) throws {
        let census = arguments.census
        let filter = arguments.ammo
        let file = try context.loadSkyrimESM()
        let localized = file.isLocalized
        let projectiles = Self.projectiles(in: file)
        let settings = ArcherySettings.resolve(
            store: GameSettingLoader.load(root: context.root, baseFile: file)
        )
        for row in settings.report {
            print(String(
                format: "%@ = %.3f [%@]",
                row.editorID,
                row.setting.value,
                row.setting.source
            ))
        }
        print("PROJ records: \(projectiles.count)")
        if census {
            printCensus(projectiles)
        }
        printAmmunition(in: file, localized: localized, projectiles: projectiles, filter: filter)
    }

    /// Every PROJ in the base plugin, keyed by raw FormID.
    private static func projectiles(in file: ESMFile) -> [UInt32: Projectile] {
        var skipped = SkippedRecords()
        let decoded = file.indexRecords(of: "PROJ", skipped: &skipped) {
            try Projectile(record: $0)
        }
        skipped.printWarnings()
        return decoded
    }

    /// The `gravity` distribution per DATA `type`. Beam and cone records carry
    /// huge values that would hide the arrow band in one set.
    private static func printCensus(_ projectiles: [UInt32: Projectile]) {
        for kind in Projectile.Kind.allCases {
            let matching = projectiles.values.filter { $0.kind == kind }
            guard !matching.isEmpty else { continue }
            print(
                "\(kind): n \(matching.count), "
                    + "gravity " + describe(matching.map(\.gravityFactor).sorted())
                    + ", speed " + describe(matching.map(\.speed).sorted())
            )
        }
        let unknown = projectiles.values.filter { $0.kind == nil }
        if !unknown.isEmpty {
            print("unknown type: n \(unknown.count)")
        }
        let arrows = projectiles.values.filter { $0.kind == .arrow }
        let nonZero = arrows.map(\.gravityFactor).filter { $0 > 0 }
        print(
            "arrow gravity non-zero: \(nonZero.count) of \(arrows.count), "
                + "all <= 1: \(nonZero.allSatisfy { $0 <= 1 })"
        )
    }

    private static func describe(_ values: [Float]) -> String {
        let finite = values.filter(\.isFinite)
        guard let low = finite.first, let high = finite.last else { return "none" }
        let mean = finite.reduce(0, +) / Float(finite.count)
        return String(format: "min %.3f max %.3f mean %.3f", low, high, mean)
    }

    /// One row per AMMO that names a PROJ: the arrow's own damage, the flight
    /// numbers it inherits, and the drop each reading of `gravity` predicts.
    private static func printAmmunition(
        in file: ESMFile,
        localized: Bool,
        projectiles: [UInt32: Projectile],
        filter: String?
    ) {
        var skipped = SkippedRecords()
        let ammunition = file.decodeRecords(of: "AMMO", skipped: &skipped) {
            try Ammunition(record: $0, localized: localized)
        }
        skipped.printWarnings()
        for ammo in ammunition {
            guard let link = ammo.projectile, let projectile = projectiles[link.rawValue] else {
                continue
            }
            let editorID = ammo.fields.editorID ?? ammo.formID.description
            if let filter, !editorID.lowercased().contains(filter.lowercased()) {
                continue
            }
            print(row(editorID: editorID, ammo: ammo, projectile: projectile))
        }
    }

    private static func row(
        editorID: String,
        ammo: Ammunition,
        projectile: Projectile
    ) -> String {
        let profile = ProjectileProfile(record: projectile)
        let asMultiplier = ProjectileFlight.drop(
            of: profile,
            atHorizontalDistance: dropDistance,
            launchDirection: SIMD3(1, 0, 0)
        ) ?? 0
        // The rejected reading, printed rather than described: `gravity` taken
        // as an acceleration in units per second squared instead of as a
        // multiplier over world gravity.
        let asAcceleration = profile.speed > 0
            ? 0.5 * projectile.gravityFactor * powf(dropDistance / profile.speed, 2)
            : 0
        return String(
            format: """
            %@: damage %.0f, PROJ %@ speed %.0f gravity %.3f range %.0f \
            -> drop at %.0f: %.1f as multiplier, %.4f as acceleration
            """,
            editorID,
            ammo.damage,
            projectile.editorID ?? projectile.formID.description,
            profile.speed,
            profile.gravityFactor,
            profile.range,
            dropDistance,
            asMultiplier,
            asAcceleration
        )
    }
}
