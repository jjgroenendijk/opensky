// Aimed-delivery checks on the real load order: the MGEF-to-PROJ chain resolves
// for a pinned destruction spell, its flight numbers are sane, a fire effect
// names the resistance actor value the code expects, and a vanilla area spell
// carries the EFIT area the code expects.

import Foundation
@testable import OpenSkyCombat
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyMagic
@testable import OpenSkyMagicInterface
@testable import OpenSkyPhysics
import simd
import Testing

struct SpellDeliveryRealDataTests {
    /// The spells this suite pins, by editor ID. `Firebolt` is the aimed
    /// point-damage shape and `Fireball` the aimed area shape; both are
    /// `Skyrim.esm` records a vanilla load order always carries.
    private enum Pinned {
        static let bolt = "Firebolt"
        static let ball = "Fireball"
    }

    private struct Stores {
        let spells: SpellStore
        let items: ItemDefinitionStore
    }

    private func stores() throws -> Stores {
        let root = try #require(RealDataEnvironment.dataRoot)
        let plugins = ActivePluginFiles.load(root: root)
        let index = RecordIndex(
            plugins: plugins,
            recordTypes: ["MGEF", "SPEL", "SCRL", "EQUP", "PROJ"]
        )
        let base = try #require(plugins.first?.1)
        return Stores(
            spells: SpellStore(index: index, effects: MagicEffectStore(index: index)),
            items: ItemDefinitionStore(file: base)
        )
    }

    private func spell(_ editorID: String, in stores: Stores) throws -> ResolvedSpell {
        try #require(
            stores.spells.spells.first { $0.editorID == editorID },
            "this load order carries no \(editorID)"
        )
    }

    /// The chain the whole item rests on: a vanilla destruction spell resolves
    /// through its MGEF to a PROJ, and that PROJ is one the flight model can
    /// integrate.
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func aVanillaDestructionSpellResolvesTheWholeEffectToProjectileChain() throws {
        let stores = try stores()
        let bolt = try spell(Pinned.bolt, in: stores)

        #expect(bolt.data?.delivery == .aimed)
        #expect(bolt.data?.castingType == .fireAndForget)
        let payload = bolt.payload(caster: .player)
        #expect(payload.isHostile, "a damage spell must resolve as hostile")
        #expect(!payload.ignoresResistance)
        let link = try #require(payload.projectile, "\(Pinned.bolt) names no PROJ")
        let profile = try #require(
            stores.items.projectileProfile(link),
            "the PROJ \(Pinned.bolt) names does not resolve to a flyable profile"
        )
        #expect(profile.isFlyable)
    }

    /// The bolt crosses a room in well under a second, drops less than a body
    /// height, and stops. The bounds are wide on purpose: they catch an error of
    /// a whole order of magnitude, not a speed the record chose.
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func thePinnedSpellsProjectileFliesSaneNumbers() throws {
        let stores = try stores()
        let bolt = try spell(Pinned.bolt, in: stores)
        let link = try #require(bolt.payload(caster: .player).projectile)
        let profile = try #require(stores.items.projectileProfile(link))

        // One thousand world units is a long interior room.
        let travel: Float = 1000
        let flightTime = travel / profile.speed
        #expect(profile.speed > 500, "speed \(profile.speed) is too slow to be a bolt")
        #expect(profile.speed < 50000, "speed \(profile.speed) is not a projectile speed")
        #expect(flightTime < 1, "\(flightTime)s to cross a room is not a bolt")

        // The closed-form drop over that flight, against the player capsule's
        // own height so the number means something a reader can picture.
        let drop = ProjectileFlight.drop(of: profile, after: flightTime)
        #expect(drop >= 0)
        #expect(
            drop < PlayerCapsule.standard.height,
            "a bolt that drops \(drop) units over \(travel) is not aimed at what it hits"
        )

        // Integrating the flight reaches the same place the closed form says.
        var state = ProjectileFlight.launch(
            from: SIMD3(), along: SIMD3(1, 0, 0), profile: profile
        )
        var steps = 0
        while state.travelled < travel, steps < 10000 {
            state = ProjectileFlight.step(state, profile: profile, dt: 1.0 / 60)
            steps += 1
        }
        #expect(state.travelled >= travel, "the bolt never covered \(travel) units")
        #expect(abs(state.position.z) - drop < 1)
    }

    /// The resistance the code scales by is the one the record names: a vanilla
    /// fire-damage effect resists through `Resist Fire`, and it is in the
    /// vanilla actor-value table so the 19.5 helper can answer for it.
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func aVanillaFireEffectNamesResistFireAsItsResistance() throws {
        let stores = try stores()
        let bolt = try spell(Pinned.bolt, in: stores)

        let damaging = try #require(
            bolt.effects.first { $0.effect?.effect.data?.flags.contains(.hostile) == true },
            "\(Pinned.bolt) carries no hostile effect entry"
        )
        let index = try #require(damaging.effect?.effect.data?.resistanceActorValue)
        #expect(index == ActorValueIndex.resistFire)
        #expect(ActorResistance.isPercentage(index: index))
        #expect(ActorResistance.isCapped(index: index))
    }

    /// The measurement the area conversion rests on: vanilla `Fireball` carries
    /// an EFIT area of 15, which is the same 15 its in-game description prints
    /// as a foot radius (<https://en.uesp.net/wiki/Skyrim:Fireball>). Pinned so
    /// the "areas are authored in feet" reading cannot quietly rot.
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func aVanillaAreaSpellCarriesItsRadiusInFeet() throws {
        let stores = try stores()
        let ball = try spell(Pinned.ball, in: stores)

        let areas = ball.record.effects.map(\.area).filter { $0 > 0 }
        #expect(areas.contains(15), "Fireball's area entries are \(areas), expected one of 15")
        // And the conversion turns that into a radius bigger than the actor it
        // is centred on, which is what an area spell has to be to catch
        // anybody standing beside its target.
        let radius = MagicAreaSettings.documentedDefaults.radius(ofArea: 15)
        #expect(radius > PlayerCapsule.standard.radius * 2)
    }

    /// How much of the vanilla spell catalogue each delivery covers, so the
    /// ground items 19.8 does and does not carry is measured rather than
    /// guessed at. Written to gitignored `.logs/`, never asserted on a count
    /// that a load order with mods would move.
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func theDeliveryCensusIsWrittenForTheRecord() throws {
        let stores = try stores()
        var counts: [String: Int] = [:]
        var implemented = 0
        for spell in stores.spells.spells {
            let delivery = spell.data?.delivery ?? .selfTarget
            counts[delivery.description, default: 0] += 1
            if SpellDelivery.isImplemented(delivery, castingType: spell.data?.castingType) {
                implemented += 1
            }
        }

        // Every vanilla load order carries aimed spells; zero would mean the
        // decode, not the census, is wrong.
        #expect(counts["aimed", default: 0] > 0)
        #expect(implemented > 0)

        let lines = counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .map { "\($0.key): \($0.value)" }
        let report = """
        Spell delivery census — \(stores.spells.spells.count) SPEL records
        \(lines.joined(separator: "\n"))
        implemented deliveries: \(implemented)
        """
        try write(report)
    }

    /// The census into a directory under gitignored `.logs/`, so a pull request
    /// can link the run rather than describe it.
    ///
    /// Resolved through `RepositoryLogs` rather than the working directory,
    /// which in a test host is `/` — the same rule every other real-data suite
    /// that leaves an artifact behind follows.
    private func write(_ report: String) throws {
        let directory = try RepositoryLogs.directory("spell-delivery")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try report.write(
            to: directory.appending(path: "census.txt"),
            atomically: true,
            encoding: .utf8
        )
    }
}
