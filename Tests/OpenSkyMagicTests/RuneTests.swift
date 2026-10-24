// Target-location casts and runes over synthetic records: the player's rune limit, the
// proximity trigger, and the rune keyword. Sources: UESP "Skyrim:Destruction" and the
// game setting `iMaxPlayerRunes`.

import OpenSkyConditions
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyMagic
@testable import OpenSkyMagicInterface
import OpenSkyPhysics
import Testing

@MainActor
struct RuneTests {
    private static let runeEffect: UInt32 = 0x70
    private static let runeKeyword: UInt32 = 0x71
    private static let victim = ReferenceKey.plugin(name: "base.esm", objectID: 0x0900)

    private let world = FakeMagicWorld()

    private static func payload(caster: ReferenceKey = .player) -> SpellPayload {
        SpellPayload(
            spell: .plugin(name: "base.esm", objectID: 0x600),
            sourcePlugin: ActiveEffectFixture.pluginName,
            caster: caster,
            entries: [MagicItemEffect(
                effect: FormID(runeEffect), magnitude: 50, area: 0, duration: 1,
                conditions: ConditionList()
            )],
            isHostile: true,
            ignoresResistance: false,
            projectile: nil,
            name: "Fire Rune"
        )
    }

    private static func rune(at x: Float, caster: ReferenceKey = .player) -> PlacedRune {
        PlacedRune(payload: payload(caster: caster), position: SIMD3(x, 0, 0), proximity: 150)
    }

    private func makeCoordinator() throws -> MagicCoordinator {
        let file = try ActiveEffectFixture.plugin(records: [
            SpellbookFixture.magicEffect(
                formID: Self.runeEffect, editorID: "RuneFireFFLocation",
                data: ActiveEffectFixture.data(flags: [.hostile, .detrimental]),
                keywords: [Self.runeKeyword]
            )
        ])
        var data = MagicSessionData()
        data.effects = MagicEffectsData(
            values: FixedActorValues(),
            store: MagicEffectStore(plugins: [(ActiveEffectFixture.pluginName, file)]),
            pluginName: ActiveEffectFixture.pluginName,
            conditionRegistry: ConditionFunctionRegistry()
        )
        world.keywords[RuneCore.keyword] = ReferenceKey(resolved: ResolvedFormID(
            plugin: ActiveEffectFixture.pluginName, objectID: Self.runeKeyword
        ))
        return MagicCoordinator(world: world, data: data)
    }

    // MARK: - Rules

    /// `iMaxPlayerRunes` is 1 in the install: a new rune replaces the player's old one.
    @Test func theNewestRuneReplacesThePlayersOldest() {
        var runes = RuneCore.placing(Self.rune(at: 0), in: [], settings: .vanilla)
        let theirs = Self.rune(at: 0, caster: Self.victim)
        runes = RuneCore.placing(theirs, in: runes, settings: .vanilla)
        runes = RuneCore.placing(Self.rune(at: 500), in: runes, settings: .vanilla)
        #expect(runes.map(\.position.x) == [0, 500])
        #expect(runes.map(\.payload.caster) == [Self.victim, .player])
    }

    @Test func theNearestActorInsideTheProximitySetsItOff() {
        let rune = Self.rune(at: 0)
        let other = ReferenceKey.plugin(name: "base.esm", objectID: 0x901)
        let far = MeleeTarget(key: other, feet: SIMD3(400, 0, 0))
        let near = MeleeTarget(key: Self.victim, feet: SIMD3(100, 0, 0))
        let caster = MeleeTarget(key: .player, feet: .zero)
        #expect(RuneCore.trigger(of: rune, among: [far, caster])?.key == nil)
        #expect(RuneCore.trigger(of: rune, among: [far, near, caster])?.key == Self.victim)
    }

    /// Fire Rune's range is 20; read as feet it is about 427 world units.
    @Test func theRangeIsReadAsFeet() {
        let perFoot = MagicAreaSettings.documentedDefaults.worldUnitsPerAreaUnit
        #expect(RuneCore.reach(range: 20) == 20 * perFoot)
        #expect(RuneCore.reach(range: -1) == 0)
    }

    // MARK: - Coordinator

    @Test func aRuneSpellWaitsWhereTheCasterAims() throws {
        let coordinator = try makeCoordinator()
        let aim = SpellAim(target: nil, position: SIMD3(300, 0, 0), candidates: [])
        #expect(coordinator.land(Self.payload(), at: aim) == 0)
        #expect(coordinator.runes.map(\.position) == [SIMD3(300, 0, 0)])
        #expect(coordinator.runes.first?.proximity == RuneCore.defaultProximity)
    }

    @Test func aHostileActorSetsTheRuneOff() throws {
        let coordinator = try makeCoordinator()
        let aim = SpellAim(target: nil, position: SIMD3(300, 0, 0), candidates: [])
        coordinator.land(Self.payload(), at: aim)
        coordinator.advanceRunes()
        #expect(coordinator.runes.count == 1)

        world.runeTargets = [MeleeTarget(key: Self.victim, feet: SIMD3(350, 0, 0))]
        coordinator.advanceRunes()
        #expect(coordinator.runes.isEmpty)
        #expect(coordinator.detonatedRunes == 1)
        let detonation = MagicCommand.detonateRune(Self.payload(), at: SIMD3(300, 0, 0))
        let commands = coordinator.takeCommands()
        #expect(commands.last == detonation)
        guard case let .spellHit(hit)? = commands.first else {
            Issue.record("The rune's hit leaves as a command: \(commands)")
            return
        }
        #expect(hit.hit.targets.map(\.key) == [Self.victim])
    }

    /// Without the rune keyword the spell lands at once on whoever stands there.
    @Test func aPlainTargetLocationSpellLandsAtOnce() throws {
        let coordinator = try makeCoordinator()
        world.keywords = [:]
        let aim = SpellAim(target: nil, position: SIMD3(300, 0, 0), candidates: [])
        coordinator.land(Self.payload(), at: aim)
        #expect(coordinator.runes.isEmpty)
    }
}
