// The session half of the archetypes: wires the runtime's lookups, carries out
// the world actions it queues, pulses cloaks, and answers the influence the
// combat loop reads. See docs/engine/magic-archetypes.md.

public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyInventoryInterface
public import OpenSkyMagicInterface
import OpenSkyProgressionInterface

extension MagicCoordinator.ArchetypeActions {
    /// The behaviour `key`'s running effects force on it.
    public func influence(of key: ReferenceKey) -> ActorMagicInfluence {
        guard
            let effects = coordinator.effects,
            let holder = coordinator.world.actorValueHolder(for: key) else { return .none }
        var influence = effects.influence(on: holder)
        if coordinator.holdEffects.isGrabbed(key) {
            influence.isParalysed = true
        }
        return influence
    }

    /// Ends `key`'s invisibility, because it acted. Returns how many effects ended.
    @discardableResult
    func breakInvisibility(of key: ReferenceKey) -> Int {
        guard let holder = coordinator.world.actorValueHolder(for: key) else { return 0 }
        return coordinator.withEffects { $0.breakInvisibility(on: holder) } ?? 0
    }

    // MARK: - World actions

    /// Carries out every world action the runtime queued, oldest first.
    func performWorldActions() {
        for action in coordinator.frameStep.takeWorldActions() {
            perform(action)
        }
        // UESP "Skyrim:Pickpocket": Harmony makes its targets "forget" a catch, but
        // "this does not work with other Pacify spells". Harmony is the vanilla calm
        // cast from self over an area; Pacify and Calm are aimed.
        for key in coordinator.frameStep.takeCalmedAround() {
            coordinator.world.forgetPickpocketCatch(of: key)
        }
        for use in coordinator.frameStep.takeHealing() {
            coordinator.world.reportSkillUse(SkillUseEvent(
                actor: use.caster, action: .spellEffect(skill: use.skill), amount: use.amount
            ))
        }
    }

    private func perform(_ action: MagicWorldAction) {
        switch (action.archetype, action.phase) {
        case (.stagger, .began):
            coordinator.pendingCommands.append(.stagger(
                action.target.key,
                magnitude: action.magnitude
            ))
        case (.spawnHazard, .began):
            guard let hazard = coordinator.associatedItem(of: action.effect) else { return }
            coordinator.pendingCommands.append(.spawnHazard(
                ReferenceKey(resolved: hazard),
                at: action.target.key
            ))
        case (.boundWeapon, .began):
            conjureBoundWeapon(action)
        case (.boundWeapon, .ended):
            dismissBoundWeapon(action)
        case (.disarm, .began):
            disarm(action.target)
        case (.summon, _), (.reanimate, _):
            coordinator.summonCommands.performCommanding(action)
        case (.detectLife, .began), (.telekinesis, .began), (.grabActor, .began),
             (.guide, .began):
            coordinator.holdEffects.performHold(action)
        case (.banish, _), (.commandSummoned, _), (.changeRace, _), (.werewolfFeed, _),
             (.light, _):
            coordinator.worldArchetypeActions.performWorldArchetype(action)
        case (.cloak, _), (.soulTrap, _), (.slowTime, _), (.stagger, .ended), (
            .spawnHazard,
            .ended
        ),
        (.disarm, .ended), (.enhanceWeapon, _), (.detectLife, .ended), (.telekinesis, .ended),
        (.grabActor, .ended), (.guide, .ended):
            break
        }
    }

    /// The Bound Weapon's `WEAP` as an inventory FormID.
    private func boundWeapon(of effect: ReferenceKey) -> FormID? {
        guard let item = coordinator.associatedItem(of: effect) else { return nil }
        return coordinator.effects?.effects.loadOrderFormID(item)
    }

    /// "Creates the specified Weapon": adds one and equips it.
    private func conjureBoundWeapon(_ action: MagicWorldAction) {
        guard
            let inventory = coordinator.world.inventory,
            let equipment = coordinator.world.equipment,
            let weapon = boundWeapon(of: action.effect)
        else { return }
        let holder = InventoryHolder(actor: action.target)
        do {
            try inventory.add(weapon, count: 1, to: holder)
            try equipment.equip(weapon, on: holder)
        } catch {
            coordinator.recordEffect(.boundWeaponFailed(reason: String(describing: error)))
        }
    }

    /// "Dispels it when the duration expires": unequips and removes it.
    private func dismissBoundWeapon(_ action: MagicWorldAction) {
        guard
            let inventory = coordinator.world.inventory,
            let weapon = boundWeapon(of: action.effect)
        else { return }
        let holder = InventoryHolder(actor: action.target)
        coordinator.world.equipment?.unequip(weapon, on: holder)
        guard inventory.count(of: weapon, in: holder) > 0 else { return }
        do {
            try inventory.remove(weapon, count: 1, from: holder)
        } catch {
            coordinator.recordEffect(.boundWeaponStayed(reason: String(describing: error)))
        }
    }

    /// Unequips every weapon `target` holds. The weapon stays in the inventory,
    /// because nothing can drop an actor's item to the ground yet.
    private func disarm(_ target: ActorValueHolder) {
        guard
            let inventory = coordinator.world.inventory,
            let equipment = coordinator.world.equipment else { return }
        let holder = InventoryHolder(actor: target)
        var unequipped = false
        for item in equipment.equipped(on: holder)
            where inventory.baselines.items.weapon(item) != nil
        {
            equipment.unequip(item, on: holder)
            unequipped = true
        }
        if unequipped, case .player = target.subject {
            coordinator.pendingCommands
                .append(.notice(coordinator.texts.castNotices[.playerDisarmed]))
        }
    }

    // MARK: - Cloaks

    /// True while `holder` runs a cloak, false while its conditions suspend every cloak it
    /// holds, as Shield Charge's do outside a charge, and nil without a cloak.
    public func cloakIsRunning(on holder: ActorValueHolder) -> Bool? {
        guard let runtime = coordinator.effects else { return nil }
        let cloaks = runtime.active(on: holder).filter { runtime.rule(of: $0) == .world(.cloak) }
        guard !cloaks.isEmpty else { return nil }
        return cloaks.contains { !$0.isSuspended }
    }

    // MARK: - Source categories
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
