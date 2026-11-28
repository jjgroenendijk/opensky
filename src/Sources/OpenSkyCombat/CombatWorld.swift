// The world side of the combat domain: what `CombatCoordinator` reads from and
// asks of the running session. The app answers it; a test passes a fake. Changes
// nothing later in a step reads go back as `CombatCommand` values.
// See docs/engine/combat.md and docs/engine/coordinators.md.

public import OpenSkyActorsInterface
public import OpenSkyBehavior
public import OpenSkyCombatInterface
public import OpenSkyConditions
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyInventoryInterface
public import OpenSkyMagicInterface
public import OpenSkyPhysics
public import OpenSkyProgressionInterface
public import OpenSkyWorldState
import simd

/// What one actor could cast, before `CombatCore` filters it.
nonisolated public struct CombatCastingFacts: Equatable, Sendable {
    public let magicka: Float
    public let spells: [CombatSpellCandidate]
    /// The actor's shouts, each as its strongest word's spell.
    public let shouts: [CombatSpellOption]

    public init(
        magicka: Float, spells: [CombatSpellCandidate], shouts: [CombatSpellOption] = []
    ) {
        self.magicka = magicka
        self.spells = spells
        self.shouts = shouts
    }
}

/// Script hits, skill uses, spell hits, and weapon enchantments, which a fight reports.
public typealias CombatReporting = ScriptHitReporting & SkillUseReporting & SpellHitApplying
    & WeaponEnchantmentApplying

/// What a fighter's perks make of a value, and the spells they pick.
public protocol CombatPerkReads {
    func perkMultiplier(at entryPoint: PerkEntryPoint, on key: ReferenceKey) -> Float
    /// What `key`'s perks make of `value`, with `subjects` bound and `seams` laid over
    /// the live conditions.
    func perkModified(
        _ value: Float,
        at entryPoint: PerkEntryPoint,
        on key: ReferenceKey,
        given conditions: (subjects: PerkEvaluationSubjects, seams: ConditionContext)
    ) -> Float
    /// `key`'s passing effects at an entry point that picks a spell, highest priority first.
    func perkChoices(
        at entryPoint: PerkEntryPoint,
        on key: ReferenceKey,
        subjects: PerkEvaluationSubjects,
        seams: ConditionContext
    ) -> [PerkEntryPointChoice]
}

/// What a fighter wears, carries, and has readied.
public protocol CombatGearReads {
    /// The player's equipment. Nil without an equipment runtime.
    var equipment: (any EquipmentAccess)? { get }
    func enchantmentProfile(of item: FormID) -> ItemEnchantmentProfile?
    /// The quality level of the player's best copy of `item`. Zero when plain.
    func temperLevel(of item: FormID) -> Int32
    /// What `key` wears, each item with its tempering level. Empty when unknown.
    func equippedItems(of key: ReferenceKey) -> [(item: FormID, temperLevel: Int32)]
    /// What `key` holds in its left hand by choice. Nil when unknown or unset.
    func leftHand(of key: ReferenceKey) -> LeftHandHold?
    func hasReadiedSpell(in hand: SpellHand) -> Bool
    /// The items the player carries, in the inventory's stable stack order.
    func playerCarriedItems() -> [FormID]
    /// The items `key` carries, in the inventory's stable stack order. Empty when unknown.
    func carriedItems(of key: ReferenceKey) -> [FormID]
    @discardableResult
    func removeOneFromPlayer(_ item: FormID) -> Bool
    /// What `key`'s running magic effects force on it, such as Calm or Etherealize.
    func magicInfluence(of key: ReferenceKey) -> ActorMagicInfluence
    /// Adds `count` of `item` to `key`'s inventory. False where it holds none.
    @discardableResult
    func addItem(_ item: FormID, count: Int32, to key: ReferenceKey) -> Bool
}

/// What `CombatCoordinator` reads from the running world. The hit, skill,
/// enchantment and spell reports pass through to the session's own runtimes.
public protocol CombatWorld: AnyObject {
    /// Where the fight's script hits, skill uses, and spell and weapon hits go.
    var reporter: any CombatReporting { get }
    /// What the fighters' perks make of a value, and the spells they pick.
    var perks: any CombatPerkReads { get }
    /// What the fighters wear, carry, and have readied.
    var gearReads: any CombatGearReads { get }
    /// The player's capsule pose. Nil without a renderer.
    var playerAttacker: MeleeAttacker? { get }
    /// Where a player shot leaves from and which way. Nil without a renderer.
    var playerShooter: ProjectileShooter? { get }
    /// The vertical field of view the player sees with, in radians. Nil without a view.
    var playerViewFOVYRadians: Float? { get }
    /// The width of the player's view over its height. Nil without a view.
    var playerViewAspect: Float? { get }
    /// The actor the player rides, or nil.
    var playerMount: ReferenceKey? { get }
    /// True while the player runs or sprints.
    var playerRuns: Bool { get }
    /// Every resident actor, with its current pose and death state.
    func residentActors() -> [CombatActorObservation]
    /// The resident actor `key`, as `residentActors()` lists it.
    func residentActor(key: ReferenceKey) -> CombatActorObservation?
    /// The actor the readout's hostility control acts on.
    func selectedActor() -> ReferenceKey?
    /// The cell `key` stands in, where its arrows stick. Nil outside a streamed world.
    func cellLocation(of key: ReferenceKey) -> CellSceneLocation?
    /// The numbers of `key`'s resolved CSTY combat style, or nil when it has none.
    func combatStyle(of key: ReferenceKey) -> CombatStyleTuning?
    /// True while the fight is in an interior cell, which shortens a flee.
    var isInInterior: Bool { get }

    func hostility(of key: ReferenceKey) -> ActorHostility
    @discardableResult
    func setHostility(_ hostility: ActorHostility, on key: ReferenceKey) -> Bool
    func awareness(of observer: ReferenceKey, toward target: ReferenceKey) -> CombatAwareness

    /// Reads `key`'s actor values by AVIF index. Nil when the session has no
    /// actor-value runtime or `key` is not resident.
    func actorValues(of key: ReferenceKey) -> ((Int32) -> Float?)?
    /// Current and maximum health. Nil when `key` has no actor values.
    func health(of key: ReferenceKey) -> (current: Float, maximum: Float)?
    /// The name the game shows for `key`, or nil for an actor without one.
    func actorName(of key: ReferenceKey) -> String?
    @discardableResult
    func damageHealth(by amount: Float, of key: ReferenceKey) -> Bool
    func damageStamina(by amount: Float, of key: ReferenceKey)
    /// Holds the player's stamina regeneration for `fBowZoomStaminaRegenDelay`.
    func pauseBowZoomStamina()
    /// A landed health hit, kept for the death effects of the actor it may kill.
    func recordHealthHit(_ hit: CombatHitRecord, on key: ReferenceKey)
    /// Whether `key` owns the perk with `editorID`.
    func ownsPerk(editorID: String, on key: ReferenceKey) -> Bool
    /// Whether any perk `key` owns has an entry at `entryPoint`, whatever its conditions.
    func ownsPerkEntry(at entryPoint: PerkEntryPoint, on key: ReferenceKey) -> Bool

    /// Nil when `key` cannot cast in this session.
    func castingFacts(of key: ReferenceKey) -> CombatCastingFacts?
    @discardableResult
    func beginCast(_ spell: ReferenceKey, by key: ReferenceKey) -> Bool
    /// Lets go of the cast. Returns true when the cast finished.
    @discardableResult
    func releaseCast(by key: ReferenceKey) -> Bool
    func cancelCast(by key: ReferenceKey)

    @discardableResult
    func moveActor(_ key: ReferenceKey, to point: SIMD3<Float>) -> Bool
    /// The same with a pace; nil picks the gait by the length of each leg.
    @discardableResult
    func moveActor(_ key: ReferenceKey, to point: SIMD3<Float>, pace: CombatPace?) -> Bool
    /// Turns `key` in place to face `point`.
    func faceActor(_ key: ReferenceKey, toward point: SIMD3<Float>)
    /// Holds `key`'s head on `target` for `seconds`, or until changed when nil.
    func lookActor(_ key: ReferenceKey, at target: ReferenceKey?, seconds: Float?)
    /// Whether `key`'s race flies (`RACE` flag 0x80).
    func actorFlies(_ key: ReferenceKey) -> Bool
    /// Whether `key`'s race is a child race (`RACE` flag Child).
    func actorIsChild(_ key: ReferenceKey) -> Bool
    /// `key` shouts the word spell `spell` along its facing. True when it went off.
    @discardableResult
    func shout(_ spell: ReferenceKey, by key: ReferenceKey) -> Bool
    func stopActor(_ key: ReferenceKey)
    func resumePackage(for key: ReferenceKey)

    /// Raises `name` on the player's behavior graph. Returns true when the
    /// graph declares the event.
    @discardableResult
    func raisePlayerGraphEvent(_ name: String) -> Bool
    func writePlayerGraphVariable(_ value: BehaviorVariableValue, named name: String)
    /// Raises `name` on an NPC's running graph. False when it runs none or lacks the event.
    @discardableResult
    func raiseActorGraphEvent(_ name: String, on key: ReferenceKey) -> Bool
    /// One variable of an NPC's running graph, or nil when it runs none or lacks the name.
    func actorGraphVariable(named name: String, on key: ReferenceKey) -> BehaviorVariableValue?
    func writeActorGraphVariable(
        _ value: BehaviorVariableValue, named name: String, on key: ReferenceKey
    )
    @discardableResult
    func playReaction(_ clip: CombatActorClip, on key: ReferenceKey) -> Bool
    /// The MATT an actor's body counts as when struck: its race's `NAM4`.
    func impactMaterial(of actor: ReferenceKey) -> FormID?

    func sweep(_ query: ShapeSweepQuery) -> ShapeSweepHit?
    func residentCells() -> Set<CellSceneLocation>
    /// Spawns a stuck arrow. Nil when the store refused it.
    func spawn(_ reference: ReferenceSpawnState, in location: CellSceneLocation) -> ReferenceKey?
    /// The resident destructible objects within `radius` of `center`, by their origin.
    func destructibleObjects(within radius: Float, of center: SIMD3<Float>) -> [MeleeTarget]
    /// Deals `amount` of hit damage to a destructible object. False when it is not one.
    @discardableResult
    func damageDestructible(_ object: ReferenceKey, amount: Float) -> Bool
    /// The key of the resident placed object `reference`, or nil.
    func destructibleKey(reference: FormID) -> ReferenceKey?

    /// Ragdoll and dynamic-body counts. The projectile fields stay zero.
    var bodyTransients: CombatTransientCounts { get }
    /// Trims ragdolls and awake bodies, and returns how many of each went.
    func trimBodyTransients(to limits: CombatTransientLimits) -> CombatTransientCounts
    /// True while `key`'s current AI package has the Ignore Combat flag.
    func packageIgnoresCombat(_ key: ReferenceKey) -> Bool
    /// True while `key` lies knocked down or gets up.
    func isKnockedDown(_ key: ReferenceKey) -> Bool
    /// `key`'s level, or nil when it has no actor values.
    func level(of key: ReferenceKey) -> Int?
    /// The health `spell` takes from the actor it lands on, before resistance.
    func spellHealthDamage(_ spell: SpellPayload) -> Float
    /// What `observer` makes of `target` through factions and relationships.
    func reaction(of observer: ReferenceKey, toward target: ReferenceKey) -> ActorReaction?
    /// True when `observer` attacks `target` on sight.
    func isHostile(_ observer: ReferenceKey, toward target: ReferenceKey) -> Bool
    /// Whether `key` is the player's follower.
    func isPlayerTeammate(_ key: ReferenceKey) -> Bool
    /// Whether `helper` counts `actor` a criminal.
    func crimeStanding(of actor: ReferenceKey, judgedBy helper: ReferenceKey)
        -> CombatCrimeStanding
    /// Whether `key` polices a crime faction as a guard.
    func isGuard(_ key: ReferenceKey) -> Bool
    /// Whether `key` attacks the player on sight for the player's crimes.
    func attacksPlayerOnSightForCrimes(_ key: ReferenceKey) -> Bool
    /// `key`'s aggro radius from its AI data, or nil when the behaviour is off.
    func aggroRadius(of key: ReferenceKey) -> AggroRadius?
    /// `key` says its aggro radius warning line to `target`, when it has one to say now.
    func sayWarning(by key: ReferenceKey, to target: ReferenceKey)
    /// `key` says its Bash combat line to `target`, when it has one to say now.
    func sayBash(by key: ReferenceKey, to target: ReferenceKey)
    /// False for an actor zero health does not kill: essential, or protected from all
    /// but the player.
    func canBeKilled(_ target: ReferenceKey, by attacker: ReferenceKey) -> Bool
    /// Plays the kill move the idle tree picks for `attempt`. False when none passes.
    func startKillMove(_ attempt: KillMoveAttempt) -> Bool
    /// True while `key` plays either half of a kill move.
    func isInKillMove(_ key: ReferenceKey) -> Bool
    /// `key`'s race attacks, in list order.
    func attacks(of key: ReferenceKey) -> [RaceAttack]
    /// The `ATKD` values of the attack `event` starts on `key`, or nil when none does.
    func attackData(of key: ReferenceKey, event: String) -> RaceAttack.Properties?
    /// The Disease spell among `key`'s race attack spells, or nil.
    func attackDisease(of key: ReferenceKey) -> ReferenceKey?
    /// Gives `key` the disease spell; on the player, the notice and the statistic too.
    /// False when `key` already has it.
    @discardableResult
    func contractDisease(_ disease: ReferenceKey, on key: ReferenceKey) -> Bool
}

extension CombatWorld {
    public var playerViewFOVYRadians: Float? {
        nil
    }

    public var playerRuns: Bool {
        false
    }

    public func attacks(of _: ReferenceKey) -> [RaceAttack] {
        []
    }

    public func attackData(of _: ReferenceKey, event _: String) -> RaceAttack.Properties? {
        nil
    }

    /// A world without races carries no disease.
    public func attackDisease(of _: ReferenceKey) -> ReferenceKey? {
        nil
    }

    @discardableResult
    public func contractDisease(_: ReferenceKey, on _: ReferenceKey) -> Bool {
        false
    }
}

extension CombatWorld where Self: CombatPerkReads {
    public var perks: any CombatPerkReads {
        self
    }
}

extension CombatWorld where Self: CombatGearReads {
    public var gearReads: any CombatGearReads {
        self
    }
}

extension CombatPerkReads {
    public func perkModified(
        _ value: Float,
        at _: PerkEntryPoint,
        on _: ReferenceKey,
        given _: (subjects: PerkEvaluationSubjects, seams: ConditionContext)
    ) -> Float {
        value
    }

    /// `key`'s perks applied to `value`, under `subjects` and, unless given, empty seams.
    func perkModified(
        _ value: Float,
        at entryPoint: PerkEntryPoint,
        on key: ReferenceKey,
        subjects: PerkEvaluationSubjects,
        seams: ConditionContext = ConditionContext()
    ) -> Float {
        perkModified(value, at: entryPoint, on: key, given: (subjects, seams))
    }

    public func perkChoices(
        at _: PerkEntryPoint,
        on _: ReferenceKey,
        subjects _: PerkEvaluationSubjects,
        seams _: ConditionContext
    ) -> [PerkEntryPointChoice] {
        []
    }
}

extension CombatGearReads {
    /// A session with no magic forces no behaviour.
    public func magicInfluence(of _: ReferenceKey) -> ActorMagicInfluence {
        .none
    }

    @discardableResult
    public func addItem(_: FormID, count _: Int32, to _: ReferenceKey) -> Bool {
        false
    }

    public func carriedItems(of _: ReferenceKey) -> [FormID] {
        []
    }

    /// A session with no equipment wears nothing, so no armour stops a blow.
    public func equippedItems(of _: ReferenceKey) -> [(item: FormID, temperLevel: Int32)] {
        []
    }
}

extension CombatWorld where Self: CombatReporting {
    public var reporter: any CombatReporting {
        self
    }
}

extension CombatWorld {
    public func isPlayerTeammate(_: ReferenceKey) -> Bool {
        false
    }

    public func sayBash(by _: ReferenceKey, to _: ReferenceKey) {}

    public func crimeStanding(
        of _: ReferenceKey, judgedBy _: ReferenceKey
    ) -> CombatCrimeStanding {
        .clean
    }

    public func isGuard(_: ReferenceKey) -> Bool {
        false
    }

    public func attacksPlayerOnSightForCrimes(_: ReferenceKey) -> Bool {
        false
    }

    @discardableResult
    public func raiseActorGraphEvent(_: String, on _: ReferenceKey) -> Bool {
        false
    }

    public func writeActorGraphVariable(
        _: BehaviorVariableValue, named _: String, on _: ReferenceKey
    ) {}

    @discardableResult
    public func moveActor(
        _ key: ReferenceKey, to point: SIMD3<Float>, pace _: CombatPace?
    ) -> Bool {
        moveActor(key, to: point)
    }

    public func faceActor(_: ReferenceKey, toward _: SIMD3<Float>) {}

    public func actorFlies(_: ReferenceKey) -> Bool {
        false
    }

    public func actorIsChild(_: ReferenceKey) -> Bool {
        false
    }

    @discardableResult
    public func shout(_: ReferenceKey, by _: ReferenceKey) -> Bool {
        false
    }

    public func destructibleObjects(within _: Float, of _: SIMD3<Float>) -> [MeleeTarget] {
        []
    }

    public func damageDestructible(_: ReferenceKey, amount _: Float) -> Bool {
        false
    }

    public func destructibleKey(reference _: FormID) -> ReferenceKey? {
        nil
    }

    public func cellLocation(of _: ReferenceKey) -> CellSceneLocation? {
        nil
    }

    /// A search of the whole list, for a session without a lookup by key.
    public func residentActor(key: ReferenceKey) -> CombatActorObservation? {
        residentActors().first { $0.key == key }
    }

    /// A session without cells fights outdoors.
    public var isInInterior: Bool {
        false
    }

    /// A session with no packages ignores nothing.
    public func level(of _: ReferenceKey) -> Int? {
        nil
    }

    public func reaction(of _: ReferenceKey, toward _: ReferenceKey) -> ActorReaction? {
        nil
    }

    public func isHostile(_: ReferenceKey, toward _: ReferenceKey) -> Bool {
        false
    }

    public func packageIgnoresCombat(_: ReferenceKey) -> Bool {
        false
    }

    public func isKnockedDown(_: ReferenceKey) -> Bool {
        false
    }

    public func aggroRadius(of _: ReferenceKey) -> AggroRadius? {
        nil
    }

    public func canBeKilled(_: ReferenceKey, by _: ReferenceKey) -> Bool {
        true
    }

    /// A session with no idle tree plays no kill move.
    public func startKillMove(_: KillMoveAttempt) -> Bool {
        false
    }

    public func isInKillMove(_: ReferenceKey) -> Bool {
        false
    }

    /// A session with no stamina pays nothing to block.
    public func damageStamina(by _: Float, of _: ReferenceKey) {}

    public func pauseBowZoomStamina() {}

    public func recordHealthHit(_: CombatHitRecord, on _: ReferenceKey) {}

    /// A session with no perks owns none.
    public func ownsPerk(editorID _: String, on _: ReferenceKey) -> Bool {
        false
    }
}
