// Telekinesis, Detect Life, and the renewal of a Grab Actor hold over synthetic MGEF
// records. Semantics: the Creation Kit wiki Magic Effect page, cited at
// `MagicArchetypeRule`.

import Foundation
import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyMagic
@testable import OpenSkyMagicInterface
import simd
import Testing

@MainActor
struct MagicHoldEffectTests {
    private static let victim = ReferenceKey.plugin(name: "base.esm", objectID: 0x0900)
    private static let rival = ReferenceKey.plugin(name: "base.esm", objectID: 0x0901)
    private static let rock = ReferenceKey.plugin(name: "base.esm", objectID: 0x0A00)
    private static let shader = FormID(0x0B00)

    /// Raw archetypes are xEdit's `wbArchtypeEnum`.
    private enum Effect {
        static let telekinesis: UInt32 = 0x80
        static let otherTelekinesis: UInt32 = 0x81
        static let detectLife: UInt32 = 0x82
        static let grab: UInt32 = 0x83
        static let guide: UInt32 = 0x84
        static let hazard: UInt32 = 0x85
    }

    private let world = FakeMagicWorld()

    /// One MGEF DATA block whose hit shader is `shader`.
    private static func data(archetype: UInt32, item: UInt32 = 0, shader: FormID? = nil) -> Data {
        var data = ActiveEffectFixture.data(associatedItem: item, archetype: archetype)
        if let shader {
            let bytes = (0 ..< 4).map { UInt8(truncatingIfNeeded: shader.rawValue >> ($0 * 8)) }
            data.replaceSubrange(32 ..< 36, with: bytes)
        }
        return data
    }

    private static var records: [Data] {
        [
            effect(Effect.telekinesis, "Telekinesis", data(archetype: 20)),
            effect(Effect.otherTelekinesis, "TelekinesisLeft", data(archetype: 20)),
            effect(Effect.detectLife, "DetectLife", data(archetype: 19, shader: shader)),
            effect(Effect.grab, "Grab", data(archetype: 45)),
            effect(Effect.guide, "Guide", data(archetype: 25, item: Effect.hazard))
        ]
    }

    private static func effect(_ formID: UInt32, _ editorID: String, _ data: Data) -> Data {
        ActiveEffectFixture.magicEffect(
            formID: formID, editorID: editorID, name: editorID, data: data
        )
    }

    private func makeCoordinator() throws -> MagicCoordinator {
        let file = try ActiveEffectFixture.plugin(
            records: ActiveEffectFixture.effectRecords + Self.records
        )
        for key in [Self.victim, Self.rival] {
            world.holders[key] = ActorValueHolder(
                key: key, subject: .actor(base: FormID(0x0F01)), cell: nil
            )
        }
        var data = MagicSessionData()
        data.effects = MagicEffectsData(
            values: FixedActorValues(),
            store: MagicEffectStore(plugins: [(ActiveEffectFixture.pluginName, file)]),
            pluginName: ActiveEffectFixture.pluginName,
            conditionRegistry: ConditionFunctionRegistry()
        )
        return MagicCoordinator(world: world, data: data)
    }

    private static func cast(
        _ formID: UInt32, on target: ReferenceKey, _ coordinator: MagicCoordinator
    ) {
        guard let holder = coordinator.world.actorValueHolder(for: target) else { return }
        _ = coordinator.withEffects { runtime in
            runtime.apply(
                [MagicItemEffect(
                    effect: FormID(formID), magnitude: 10, area: 0, duration: 0,
                    conditions: ConditionList()
                )],
                fromPlugin: ActiveEffectFixture.pluginName,
                source: ActiveEffectSource(
                    kind: .spell, record: .plugin(name: "base.esm", objectID: 0x600)
                ),
                caster: .player,
                on: holder
            )
        }
    }

    private static func notices(_ commands: [MagicCommand]) -> Int {
        commands.count(where: {
            if case .notice = $0 {
                true
            } else {
                false
            }
        })
    }

    private static func painted(_ commands: [MagicCommand], shown: Bool) -> [ReferenceKey] {
        commands.compactMap {
            if case let .paintActor(key, _, _, isShown) = $0, isShown == shown {
                key
            } else {
                nil
            }
        }
    }

    /// The first landing picks the loose body, a second effect finds the hands full,
    /// and the body is thrown along the aim once no landing renews the hold.
    @Test func telekinesisHoldsSteersAndThrows() throws {
        let coordinator = try makeCoordinator()
        world.looseBody = Self.rock
        world.aimRays[.player] = MagicAimRay(origin: .zero, direction: SIMD3(0, 1, 0))
        world.heldBodies[Self.rock] = MagicHeldBody(position: .zero, velocity: .zero, mass: 2)
        Self.cast(Effect.telekinesis, on: .player, coordinator)
        let grabbed = coordinator.frameStep.advanceEffects(delta: 0)
        #expect(coordinator.playerGrabbedReference == Self.rock)
        #expect(grabbed.contains(.playerGrab(Self.rock, held: true)))

        Self.cast(Effect.telekinesis, on: .player, coordinator)
        Self.cast(Effect.otherTelekinesis, on: .player, coordinator)
        #expect(Self.notices(coordinator.frameStep.advanceEffects(delta: 0)) == 1)

        _ = coordinator.frameStep.advanceEffects(delta: 0.1)
        #expect(world.pushes.first?.body == Self.rock)
        var commands: [MagicCommand] = []
        for _ in 0 ..< 20 {
            commands += coordinator.frameStep.advanceEffects(delta: 0.1)
        }
        #expect(commands.contains(.playerGrab(Self.rock, held: false)))
        #expect(coordinator.playerGrabbedReference == nil)
    }

    /// Living actors in range are painted with the hit shader, and unpainted on release.
    @Test func detectLifePaintsThenClears() throws {
        let coordinator = try makeCoordinator()
        world.living = [Self.victim, Self.rival]
        Self.cast(Effect.detectLife, on: .player, coordinator)
        let shown = coordinator.frameStep.advanceEffects(delta: 0)
        #expect(Set(Self.painted(shown, shown: true)) == [Self.victim, Self.rival])

        world.living = [Self.victim]
        Self.cast(Effect.detectLife, on: .player, coordinator)
        let narrowed = coordinator.frameStep.advanceEffects(delta: 0)
        #expect(Self.painted(narrowed, shown: false) == [Self.rival])

        var commands: [MagicCommand] = []
        for _ in 0 ..< 20 {
            commands += coordinator.frameStep.advanceEffects(delta: 0.1)
        }
        #expect(Self.painted(commands, shown: false) == [Self.victim])
    }

    /// A second landing renews the hold instead of grabbing again.
    @Test func grabActorRenewsItsHold() throws {
        let coordinator = try makeCoordinator()
        Self.cast(Effect.grab, on: Self.victim, coordinator)
        Self.cast(Effect.grab, on: Self.victim, coordinator)
        _ = coordinator.frameStep.advanceEffects(delta: 0)
        #expect(coordinator.holds.count(where: { $0.kind == .grabActor }) == 1)
    }

    @Test func guideWithoutAPathSaysSo() throws {
        let coordinator = try makeCoordinator()
        world.guide = .noPath
        Self.cast(Effect.guide, on: .player, coordinator)
        #expect(Self.notices(coordinator.frameStep.takeCommands()) == 1)
        #expect(world.placedHazards.isEmpty)
    }
}
