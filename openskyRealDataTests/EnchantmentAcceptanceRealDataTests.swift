// The 19.9 acceptance chain, end to end against the user's own install
// (issue #472): a real enchanted weapon landing real hits and running down, and a
// real Fortify One-Handed armour enchantment measurably changing a damage number.
//
// Read-only against the install and headless: it builds the same engine types the
// app wires — the real `EnchantmentStore`, the real `ItemDefinitionStore` with its
// `EITM` resolver, the real `ActiveEffectRuntime` — with no window and no renderer,
// so what it proves is the chain rather than the panel. The panels are covered by
// `ItemsSectionTests`, `InventoryEquipmentPanelTests` and `InventoryMenuPanelTests`;
// this covers what those readouts print about.
//
// Neither half is pinned to a FormID it did not have to be. Both the weapon and
// the armour are found by *searching* the load order — the weapon for a metered
// contact enchantment whose effect this engine can actually carry out, the armour
// for one whose effect moves One-Handed Modifier — so the chain keeps working when a
// load order moves which item carries what. The one pinned FormID is UESP's
// published charge row, asserted beside the searched weapon rather than instead of
// it: that row's own enchantment is an Absorb effect, which is an archetype item
// 19.6 counts rather than applies.
//
// It writes a summary into gitignored `logs/` so a pull request can link the run.
// Counts, editor IDs and numbers only: no game bytes leave the machine
// (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import opensky
import Testing

struct EnchantmentAcceptanceRealDataTests {
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    /// The weapon UESP prints as 1000 charge at 18 per use — 55 uses.
    private static let publishedWeaponID: UInt32 = 0x000A_CC70

    /// The stores the chain needs, loaded once.
    private struct Indexes {
        let plugin: String
        let index: RecordIndex
        let effects: MagicEffectStore
        let enchantments: EnchantmentStore
        let items: ItemDefinitionStore

        init(root: GameDataRoot) throws {
            let plugins = ActivePluginFiles.load(root: root)
            plugin = try #require(plugins.first?.name)
            index = RecordIndex(
                plugins: plugins,
                recordTypes: ["MGEF", "ENCH", "WEAP", "ARMO"]
            )
            let effects = MagicEffectStore(index: index)
            self.effects = effects
            let enchantments = EnchantmentStore(index: index, effects: effects)
            self.enchantments = enchantments
            items = try ItemDefinitionStore(
                file: ESMFile(url: root.dataURL.appending(path: plugin)),
                enchantments: ItemEnchantmentResolver(
                    store: enchantments,
                    pluginName: plugin
                )
            )
        }

        /// One item's resolved enchantment, or nil when it carries none.
        func profile(of formID: UInt32) -> ItemEnchantmentProfile? {
            items.definition(FormID(formID))
                .flatMap { ItemEnchantmentProfile.resolve($0, using: enchantments) }
        }

        /// The first worn enchantment whose effect list moves `index`, searched
        /// in ascending FormID order so the answer is the same on every run.
        func firstWornProfile(moving actorValue: Int32) -> ItemEnchantmentProfile? {
            first { $0.isWorn && moves(actorValue, in: $0) }
        }

        /// The first metered contact enchantment whose effect list this engine can
        /// actually carry out on health.
        ///
        /// Searched rather than pinned, and the archetype filter is the point: the
        /// weapon UESP's charge table happens to name carries an Absorb effect,
        /// which is an archetype item 19.6 counts rather than applies. Picking a
        /// weapon by hand would either pin that gap into the acceptance or pin a
        /// FormID that a load order can move.
        func firstDamagingContactProfile() -> ItemEnchantmentProfile? {
            let health = ActorValueIdentity.storedIndices[.health] ?? 24
            return first { profile in
                profile.isContact && profile.fullCharge.isMetered
                    && moves(health, in: profile, implementedOnly: true, detrimental: true)
            }
        }

        private func first(
            where matches: (ItemEnchantmentProfile) -> Bool
        ) -> ItemEnchantmentProfile? {
            for formID in items.definitions.keys.sorted() {
                guard let profile = profile(of: formID), matches(profile) else { continue }
                return profile
            }
            return nil
        }

        /// Whether any of `profile`'s entries acts on `actorValue`, optionally
        /// narrowed to an archetype this engine implements and to a detrimental
        /// effect — which together are what "the struck actor loses health" needs.
        private func moves(
            _ actorValue: Int32,
            in profile: ItemEnchantmentProfile,
            implementedOnly: Bool = false,
            detrimental: Bool = false
        ) -> Bool {
            profile.entries.contains { entry in
                guard
                    let data = effects.resolve(entry, fromPlugin: profile.sourcePlugin)?
                        .effect.data,
                    data.relatedActorValue == actorValue
                else { return false }
                if
                    implementedOnly,
                    !MagicEffectPlanner.implementedArchetypes.contains(data.archetype)
                {
                    return false
                }
                return !detrimental || data.flags.contains(.detrimental)
            }
        }
    }

    /// The same stack the app wires, minus the window: the target starts at 500 of
    /// everything and regenerates nothing, so a number the test reads is only ever
    /// what the enchantment moved.
    @MainActor
    private struct Session {
        var effects: ActiveEffectRuntime
        let store: WorldStateStore

        init(indexes: Indexes) {
            let store = WorldStateStore()
            self.store = store
            effects = ActiveEffectRuntime(
                values: ActorValueRuntime(
                    store: store,
                    baselines: ActorValueBaselineResolver(
                        fallback: ActorValueBaseline(
                            maximums: ActorValues(repeating: 500),
                            regenPercentPerSecond: .zero
                        )
                    )
                ),
                effects: indexes.effects
            )
        }
    }

    private static let target = ActorValueHolder(
        key: .plugin(name: "skyrim.esm", objectID: 0x0001_3BAC),
        subject: .player
    )

    @Test(.enabled(if: Self.dataRoot != nil))
    @MainActor
    func anEnchantedWeaponAppliesItsEffectsAndAFortifyArmorChangesADamageNumber() throws {
        let indexes = try Indexes(root: #require(Self.dataRoot))
        var session = Session(indexes: indexes)
        let target = Self.target

        // 1. A real enchanted weapon, resolved the way an equip resolves it, whose
        // effect this engine can carry out.
        let weapon = try #require(indexes.firstDamagingContactProfile())
        #expect(weapon.isContact)
        let fullCharge = weapon.fullCharge
        #expect(fullCharge.usesRemaining >= 1)
        // The published charge table, on the weapon UESP prints it for: the same
        // ratio, on a weapon whose Absorb archetype item 19.6 counts rather than
        // applies. Pinned here too so the acceptance covers both facts.
        let published = try #require(indexes.profile(of: Self.publishedWeaponID))
        #expect(published.fullCharge.usesRemaining == 55)

        // 2. Two landed hits apply its effects and take two uses off it.
        let healthBefore = session.effects.values.current(of: target).health
        var reports: [WeaponEnchantmentReport] = []
        for _ in 0 ..< 2 {
            reports.append(WeaponEnchantmentApplication.apply(
                WeaponEnchantmentHit(
                    profile: weapon,
                    attacker: .player,
                    target: target.key,
                    position: .zero
                ),
                owner: .player,
                target: target,
                using: &session.effects
            ))
        }
        let healthAfter = session.effects.values.current(of: target).health
        let lastCharge = try #require(reports.last?.charge)
        let everyHitFired = reports.allSatisfy(\.didFire)
        #expect(everyHitFired)
        #expect(lastCharge.remaining == fullCharge.remaining - 2 * weapon.costPerUse)
        #expect(lastCharge.usesRemaining == fullCharge.usesRemaining - 2)
        // Absorb Health is detrimental, so the struck actor lost health. The
        // magnitude itself is the record's; what this asserts is that the hit
        // reached the actor-value surface at all.
        #expect(healthAfter < healthBefore)

        // 3. The charge is in the world-state store, so it would land in a save.
        let ledger = EnchantmentLedger(store: session.store)
        #expect(
            ledger.charge(of: weapon, on: .player).usesRemaining
                == fullCharge.usesRemaining - 2
        )

        // 4. A real Fortify One-Handed armour enchantment, worn.
        let oneHanded = try #require(ActorValueIdentity.index(named: "One-Handed Modifier"))
        let armor = try #require(indexes.firstWornProfile(moving: oneHanded))
        let plainDamage = Self.damage(reading: session.effects.values)
        let worn = WornEnchantmentApplication.reconcile(
            worn: [armor], on: .player, using: &session.effects
        )
        #expect(worn.storedCount >= 1)
        let points = try #require(session.effects.values.value(at: oneHanded, on: .player))
        #expect(points > 0)

        // 5. The damage number moved, by exactly the documented multiplier.
        let fortifiedDamage = Self.damage(reading: session.effects.values)
        #expect(fortifiedDamage.applied > plainDamage.applied)
        #expect(fortifiedDamage.attackMultiplier == 1 + points / 100)
        #expect(fortifiedDamage.applied == plainDamage.base * fortifiedDamage.attackMultiplier)

        // 6. Taking it off puts the number back.
        WornEnchantmentApplication.removeAll(on: .player, using: &session.effects)
        #expect(session.effects.values.value(at: oneHanded, on: .player) == 0)
        #expect(Self.damage(reading: session.effects.values).applied == plainDamage.applied)

        try writeSummary(Outcome(
            weapon: weapon,
            charge: (fullCharge, lastCharge),
            health: (healthBefore, healthAfter),
            armor: armor,
            points: points,
            damage: (plainDamage, fortifiedDamage)
        ))
    }

    /// One landed one-handed swing of a fixed ten-point weapon, unblocked, with
    /// whatever fortify the reader reports. A fixed weapon rather than the real
    /// one, so the only thing that can move the number is the enchantment.
    @MainActor
    private static func damage(reading values: ActorValueRuntime) -> MeleeDamageResult {
        MeleeDamage.resolve(
            weapon: MeleeWeaponProfile(damage: 10, reach: 1, handType: .sword),
            block: nil,
            settings: .synthetic,
            attackMultiplier: CombatFortifyBonus.melee(handType: .sword) {
                values.value(at: $0, on: .player)
            }
        )
    }

    /// Everything the run measured, so the writer takes one argument rather than
    /// six.
    private struct Outcome {
        let weapon: ItemEnchantmentProfile
        let charge: (before: EnchantmentCharge, after: EnchantmentCharge)
        let health: (before: Float, after: Float)
        let armor: ItemEnchantmentProfile
        let points: Float
        let damage: (plain: MeleeDamageResult, fortified: MeleeDamageResult)
    }

    /// A summary into gitignored `logs/`, so a pull request can link the run
    /// rather than describe it.
    ///
    /// Anchored on the source file rather than the working directory, which in a
    /// test host is `/` — the same rule the other real-data suites that leave
    /// artifacts behind follow.
    private func writeSummary(_ outcome: Outcome) throws {
        let weapon = outcome.weapon
        let charge = outcome.charge
        let health = outcome.health
        let armor = outcome.armor
        let points = outcome.points
        let damage = outcome.damage
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "logs")
            .appending(path: "enchantment-acceptance")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let text = """
        19.9 enchantment acceptance, issue #472
        weapon:         \(weapon.item) \(weapon.name)
        charge:         \(charge.0.describedLine) -> \(charge.1.describedLine)
        target health:  \(health.0) -> \(health.1)
        worn armor:     \(armor.item) \(armor.name)
        fortify points: \(points)
        melee damage:   \(damage.0.applied) -> \(damage.1.applied) \
        (x\(damage.1.attackMultiplier))

        """
        try text.write(
            to: directory.appending(path: "acceptance.txt"),
            atomically: true,
            encoding: .utf8
        )
    }
}
