// `archery`: walk the ammunition chain the way a shot does — AMMO to the PROJ
// it launches to the flight the two produce (issue #196, roadmap item 15.5).
//
// This is the probe that settles what PROJ's `gravity` member means. Neither
// UESP nor xEdit states its unit, and the two candidate readings are
// distinguishable by looking at the data: an acceleration in world units per
// second squared would have to be in the hundreds to move an arrow at all,
// while a dimensionless multiplier over world gravity would sit near one. The
// `--census` report prints the distribution over every PROJ in the load order
// so the answer is read rather than assumed, and the per-arrow rows print the
// drop each reading predicts at a fixed distance so the difference is in front
// of the reader instead of in a footnote.
//
// Read-only. Output is plain text and stable enough to grep.

import Foundation

enum ArcheryCommand {
    /// The distance the per-arrow drop is reported at. A round number inside
    /// `fVisibleNavmeshMoveDist`, so the figure is one a shot could actually
    /// take.
    static let dropDistance: Float = 1000

    static func run(context: CLIContext, scanner: inout ArgumentScanner) throws {
        let census = scanner.flag("--census")
        let filter = try scanner.option("--ammo")
        try scanner.finish()
        let file = try context.loadSkyrimESM()
        let localized = (try? file.pluginHeader().isLocalized) ?? false
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
        guard
            let group = file.topGroup(of: "PROJ"),
            let children = try? group.children()
        else { return [:] }
        var decoded: [UInt32: Projectile] = [:]
        for case let .record(record) in children where !record.isDeleted {
            guard let projectile = try? Projectile(record: record) else { continue }
            decoded[projectile.formID.rawValue] = projectile
        }
        return decoded
    }

    /// The distribution that settles the `gravity` unit question.
    ///
    /// Broken out by DATA `type`, because the whole-set figures do not settle
    /// anything on their own: a handful of beam and cone records carry
    /// enormous values in both members, and lumping them in with the arrows
    /// hides the band the arrows actually sit in.
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
        guard
            let group = file.topGroup(of: "AMMO"),
            let children = try? group.children()
        else { return }
        for case let .record(record) in children where !record.isDeleted {
            guard
                let ammo = try? Ammunition(record: record, localized: localized),
                let link = ammo.projectile,
                let projectile = projectiles[link.rawValue]
            else { continue }
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
