// The session half of the archetypes: wires the runtime's lookups, carries out
// the world actions it queues, pulses cloaks, and answers the influence the
// combat loop reads. See docs/engine/magic-archetypes.md.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface

extension MagicCoordinator {
    /// How often a cloak casts its spell on the actors around it. An OpenSky
    /// number: the wiki names no rate, and a per-second effect pays on whole seconds.
    public static let cloakPulseSeconds: Float = 1

    /// The keyword Turn Undead requires on its target.
    public static let undeadKeyword = "ActorTypeUndead"

    /// Gives the runtime the lookups it cannot make itself.
    func wireArchetypeLookups() {
        withEffects { runtime in
            runtime.holderResolver = { [weak self] key in
                self?.world.actorValueHolder(for: key)
            }
            runtime.isUndead = { [weak self] holder in
                self?.world.actorHasKeyword(Self.undeadKeyword, on: holder) ?? false
            }
            runtime.sourceCategory = { [weak self] source in
                self?.category(of: source) ?? .other
            }
            runtime.entryConditions = { [weak self] effect in
                self?.entryConditions(of: effect)
            }
        }
    }

    /// The behaviour `key`'s running effects force on it.
    public func influence(of key: ReferenceKey) -> ActorMagicInfluence {
        guard let effects, let holder = world.actorValueHolder(for: key) else { return .none }
        return effects.influence(on: holder)
    }

    /// Ends `key`'s invisibility, because it acted. Returns how many effects ended.
    @discardableResult
    public func breakInvisibility(of key: ReferenceKey) -> Int {
        guard let holder = world.actorValueHolder(for: key) else { return 0 }
        return withEffects { $0.breakInvisibility(on: holder) } ?? 0
    }

    // MARK: - World actions

    /// Carries out every world action the runtime queued, oldest first.
    func performWorldActions() {
        for action in takeWorldActions() {
            perform(action)
        }
    }

    private func perform(_ action: MagicWorldAction) {
        switch (action.archetype, action.phase) {
        case (.stagger, .began):
            pendingCommands.append(.stagger(action.target.key, magnitude: action.magnitude))
        case (.spawnHazard, .began):
            guard let hazard = associatedItem(of: action.effect) else { return }
            pendingCommands.append(.spawnHazard(
                ReferenceKey(resolved: hazard),
                at: action.target.key
            ))
        case (.boundWeapon, .began):
            conjureBoundWeapon(action)
        case (.boundWeapon, .ended):
            dismissBoundWeapon(action)
        case (.disarm, .began):
            disarm(action.target)
        case (.cloak, _), (.soulTrap, _), (.stagger, .ended), (.spawnHazard, .ended),
             (.disarm, .ended):
            break
        }
    }

    private func associatedItem(of effect: ReferenceKey) -> ResolvedFormID? {
        guard let store = effects?.effects, let resolved = store.effect(key: effect) else {
            return nil
        }
        return store.associatedItem(of: resolved)
    }

    /// The Bound Weapon's `WEAP` as an inventory FormID.
    private func boundWeapon(of effect: ReferenceKey) -> FormID? {
        guard let item = associatedItem(of: effect) else { return nil }
        return effects?.effects.loadOrderFormID(item)
    }

    /// "Creates the specified Weapon": adds one and equips it.
    private func conjureBoundWeapon(_ action: MagicWorldAction) {
        guard
            let inventory = world.inventory,
            let equipment = world.equipment,
            let weapon = boundWeapon(of: action.effect)
        else { return }
        let holder = InventoryHolder(actor: action.target)
        do {
            try inventory.add(weapon, count: 1, to: holder)
            try equipment.equip(weapon, on: holder)
        } catch {
            recordEffect(.boundWeaponFailed(reason: String(describing: error)))
        }
    }

    /// "Dispels it when the duration expires": unequips and removes it.
    private func dismissBoundWeapon(_ action: MagicWorldAction) {
        guard
            let inventory = world.inventory,
            let weapon = boundWeapon(of: action.effect)
        else { return }
        let holder = InventoryHolder(actor: action.target)
        world.equipment?.unequip(weapon, on: holder)
        guard inventory.count(of: weapon, in: holder) > 0 else { return }
        do {
            try inventory.remove(weapon, count: 1, from: holder)
        } catch {
            recordEffect(.boundWeaponStayed(reason: String(describing: error)))
        }
    }

    /// Unequips every weapon `target` holds. The weapon stays in the inventory,
    /// because nothing can drop an actor's item to the ground yet.
    private func disarm(_ target: ActorValueHolder) {
        guard let inventory = world.inventory, let equipment = world.equipment else { return }
        let holder = InventoryHolder(actor: target)
        for item in equipment.equipped(on: holder)
            where inventory.baselines.items.weapon(item) != nil
        {
            equipment.unequip(item, on: holder)
        }
    }

    // MARK: - Cloaks

    /// Casts each running cloak's spell on the hostile actors inside its radius,
    /// once per `cloakPulseSeconds`. A cloak's magnitude is its radius, in units.
    func pulseCloaks(delta: Float) {
        guard delta.isFinite, delta > 0 else { return }
        cloakClock += delta
        guard cloakClock >= Self.cloakPulseSeconds else { return }
        cloakClock = min(cloakClock - Self.cloakPulseSeconds, Self.cloakPulseSeconds)
        guard let runtime = effects else { return }
        for holder in world.regeneratingHolders() {
            for effect in runtime.active(on: holder)
                where runtime.rule(of: effect) == .world(.cloak)
            {
                pulse(effect, from: holder, world: world)
            }
        }
    }

    private func pulse(
        _ cloak: ActiveEffect,
        from holder: ActorValueHolder,
        world: any MagicWorld
    ) {
        guard
            let item = associatedItem(of: cloak.effect),
            let spell = caster?.spellbook.spells.spell(item)
        else { return }
        let targets = world.cloakTargets(around: holder.key, radius: cloak.peakMagnitude)
            .filter { $0 != holder.key }
        guard !targets.isEmpty else { return }
        applySpellHit(SpellHit(
            payload: spell.payload(caster: holder.key),
            targets: targets.map { SpellHitTarget(key: $0) }
        ))
    }

    // MARK: - Source categories

    /// What kind of record `source` is, for Cure Disease and Cure Poison.
    private func category(of source: ActiveEffectSource) -> ActiveEffectSourceCategory {
        switch source.kind {
        case .spell:
            caster?.spellbook.spells.spell(key: source.record)?.spellType == .disease
                ? .disease : .other
        case .potion:
            isPoison(source.record) ? .poison : .other
        case .ingredient, .enchantment, .perk, .ability:
            .other
        }
    }

    /// Whether `record` is an `ALCH` with the Poison flag.
    private func isPoison(_ record: ReferenceKey) -> Bool {
        guard
            case let .plugin(plugin, objectID) = record,
            let items = world.inventory?.baselines.items,
            let id = effects?.effects.loadOrderFormID(
                ResolvedFormID(plugin: plugin, objectID: objectID)
            )
        else { return false }
        return items.ingestibles[id.rawValue]?.flags.contains(.poison) == true
    }
}

nonisolated extension InventoryHolder {
    /// The inventory of the actor behind `holder`.
    public init(actor holder: ActorValueHolder) {
        let owner: InventoryOwner = switch holder.subject {
        case .player: .player
        case let .actor(base): .actor(base: base)
        case .generated: .generated
        }
        self.init(key: holder.key, owner: owner, cell: holder.cell)
    }
}
