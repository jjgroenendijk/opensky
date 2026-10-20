// The shell around `LockCore` and `LockpickingSession`: lock state in the world
// store, keys and lockpicks in the inventory, perks and skill use through the port.
// See docs/engine/locks.md.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyInventoryInterface
import OpenSkyProgressionInterface
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What the lock coordinator reads from the rest of the game.
@MainActor
public protocol LockWorld: AnyObject, SkillUseReporting {
    /// The player's current Lockpicking skill.
    var lockpickingSkill: Float { get }
    /// What the player's perks make of `value` at `entryPoint`, with `lock` bound as the
    /// locked reference and `level` answering its `GetLockLevel`.
    func perkValue(
        _ value: Float, at entryPoint: PerkEntryPoint, lock: ReferenceKey, level: UInt8
    ) -> Float
    /// The doors and containers with `XLOC` in the loaded cells.
    func lockables() -> [PlacedInteraction]
    /// An item's display name, for the key a lock names.
    func itemName(_ item: FormID) -> String
    /// The player's Filter Activation perks with `reference` bound as the target.
    /// Non-zero blocks the activation.
    func activationFilter(of reference: ReferenceKey) -> Float
    /// Reports picking `lock` as a crime when it is owned and someone sees it.
    /// Returns the bounty, 0 when nobody saw or the lock is the player's to open.
    func reportLockpickingCrime(on lock: ReferenceKey) -> Int32
    /// Counts one picked lock on the journal's "Locks Picked" stat.
    func countLockPicked()
}

extension LockWorld {
    public func activationFilter(of _: ReferenceKey) -> Float {
        0
    }

    public func reportLockpickingCrime(on _: ReferenceKey) -> Int32 {
        0
    }

    public func countLockPicked() {}
}

/// Why a lockpicking session did not start.
nonisolated public enum LockpickingRefusal: Error, Equatable, Sendable {
    case noRuntime
    case unknownReference(FormID)
    case notLocked
    case requiresKey
    case noLockpicks
}

/// How the last lockpicking session ended, for the sidebar.
nonisolated public struct LockpickingOutcome: Equatable, Sendable {
    public let difficulty: LockDifficulty
    public let opened: Bool
    public let picksBroken: Int
    public let experience: Float
    public let keyRewarded: Bool

    public init(
        difficulty: LockDifficulty,
        opened: Bool,
        picksBroken: Int,
        experience: Float,
        keyRewarded: Bool
    ) {
        self.difficulty = difficulty
        self.opened = opened
        self.picksBroken = picksBroken
        self.experience = experience
        self.keyRewarded = keyRewarded
    }
}

/// The perk entry points lockpicking reads, by their xEdit index.
nonisolated public enum LockpickingEntryPoint {
    public static let sweetSpot = PerkEntryPoint.modLockpickSweetSpot
    public static let startingArc = PerkEntryPoint.setLockpickStartingArc
    public static let unbreakable = PerkEntryPoint.makeLockpicksUnbreakable
    public static let keyReward = PerkEntryPoint.modLockpickingKeyRewardChance
    public static let crimeChance = PerkEntryPoint.modLockpickingCrimeChance
}

/// The lock a session is picking, as it stood when the session began.
nonisolated struct LockpickingTarget: Sendable {
    let key: ReferenceKey
    let state: ReferenceLockState
    let perks: LockpickingPerkValues
}

@MainActor
public final class LockCoordinator {
    public private(set) var items: WorldItemRuntime?
    public var settings = LockpickingSettings.documentedDefaults
    public var texts = LockTexts.vanilla
    /// The `LKPK` default object. Nil keeps every lock shut to picking.
    public var lockpickItem: FormID?
    /// Sidebar override: treat the player as carrying every lock's key.
    public var playerCarriesEveryKey = false
    public var random = LockpickingRandom(seed: 0x4F_7065_6E53_6B79)
    let world: any LockWorld
    /// Takes `LOCK`.
    public weak var storyEvents: (any StoryEventReporting)?
    /// Health of the pick in hand. UESP: it carries over between locks.
    public internal(set) var pickHealth: Float = 1
    public internal(set) var session: LockpickingSession?
    public internal(set) var sessionTarget: InteractionTarget?
    var sessionLock: LockpickingTarget?
    var sessionExperience: Float = 0
    public internal(set) var lastOutcome: LockpickingOutcome?
    public internal(set) var lastAction = LockActionOutcome.idle
    /// The lock the sidebar works on.
    public var selectedLock: FormID?

    public init(world: any LockWorld) {
        self.world = world
    }

    public func wire(items: WorldItemRuntime) {
        self.items = items
    }

    // MARK: - Lock state

    /// The lock of the reference behind `interaction`, or nil when it has none.
    public func lock(
        of interaction: PlacedInteraction
    ) -> (key: ReferenceKey, state: ReferenceLockState)? {
        guard let items, let entry = items.references?.referenceEntry(formID: interaction.reference)
        else { return nil }
        let delta = items.store.component(ReferenceLockState.self, for: entry.key)
        guard let state = ReferenceLockState.resolve(baseline: interaction.lock, delta: delta)
        else { return nil }
        return (entry.key, state)
    }

    public func carriesKey(_ key: FormID?) -> Bool {
        guard let key else { return false }
        if playerCarriesEveryKey {
            return true
        }
        guard let items else { return false }
        return items.inventory.count(of: key, in: items.player) > 0
    }

    /// The use-key gate. A Filter Activation perk blocks the press first, as a
    /// werewolf cannot open doors. A carried key unlocks the target and lets it through.
    public func gate(_ target: InteractionTarget) -> InventoryResult<ActivationRefusal?> {
        if
            let entry = items?.references?.referenceEntry(formID: target.interaction.reference),
            world.activationFilter(of: entry.key) != 0
        {
            lastAction = .blockedByPerk(name: target.interaction.name)
            return InventoryResult(.filteredByPerk)
        }
        guard let lock = lock(of: target.interaction) else { return InventoryResult(nil) }
        switch LockCore.decide(lock: lock.state, carriesKey: carriesKey(lock.state.key)) {
        case .proceed:
            return InventoryResult(nil)
        case let .unlockWithKey(key):
            let unlocked = write(lock.state, locked: false, for: lock.key)
            lastAction = .unlockedWithKey(name: target.interaction.name)
            let notice = texts.keyNotice(
                key: world.itemName(key), isContainer: target.interaction.action == .search
            )
            return InventoryResult(nil, commands: unlocked + [.showNotice(notice)])
        case let .refuse(refusal):
            lastAction = .refused(
                name: target.interaction.name, difficulty: difficulty(of: lock.state)
            )
            return InventoryResult(refusal)
        }
    }

    public func difficulty(of state: ReferenceLockState) -> LockDifficulty {
        state.difficulty(noviceMaximum: settings.noviceMaximum)
    }

    /// Why a refused press opens no minigame, or nil.
    public func refusalNotice(level: UInt8) -> LockNotice? {
        let band = LockDifficulty(level: level, noviceMaximum: settings.noviceMaximum)
        return LockCore.refusalNotice(for: band, lockpicks: lockpickCount)
    }

    public func labelled(_ interaction: PlacedInteraction) -> PlacedInteraction {
        LockCore.labelled(
            interaction, lock: lock(of: interaction)?.state,
            texts: texts, noviceMaximum: settings.noviceMaximum
        )
    }

    /// Forces the lock open or shut. The level and key stay as they are.
    public func setLocked(
        _ interaction: PlacedInteraction, locked: Bool
    ) -> InventoryResult<LockActionOutcome> {
        guard let lock = lock(of: interaction) else {
            return InventoryResult(record(.noLock(name: interaction.name)))
        }
        let commands = write(lock.state, locked: locked, for: lock.key)
        return InventoryResult(
            record(.lockChanged(name: interaction.name, locked: locked)), commands: commands
        )
    }

    /// Asks for a prompt refresh, because the lock band in the label changed.
    func write(
        _ state: ReferenceLockState, locked: Bool, for key: ReferenceKey
    ) -> [InventoryCommand] {
        guard let items else { return [] }
        var updated = state
        updated.isLocked = locked
        items.store.set(updated, for: key, in: items.references?.cellLocation(of: key))
        return [.refreshInteractionTarget]
    }

    @discardableResult
    public func record(_ outcome: LockActionOutcome) -> LockActionOutcome {
        lastAction = outcome
        return outcome
    }

    // MARK: - Lockpicking

    public var lockpickCount: Int32 {
        guard let items, let lockpickItem else { return 0 }
        return items.inventory.count(of: lockpickItem, in: items.player)
    }

    /// Starts the minigame on `target`. The sweet spot is drawn from `random`.
    public func beginLockpicking(_ target: InteractionTarget) throws(LockpickingRefusal) {
        guard items != nil else { throw .noRuntime }
        guard let lock = lock(of: target.interaction) else {
            throw .unknownReference(target.interaction.reference)
        }
        guard lock.state.isLocked else { throw .notLocked }
        let difficulty = difficulty(of: lock.state)
        guard difficulty.isPickable else { throw .requiresKey }
        let picks = lockpickCount
        guard picks > 0 else { throw .noLockpicks }
        let perks = perkValues(lock: lock.key, level: lock.state.level)
        let parameters = LockpickingParameters.make(
            difficulty: difficulty,
            skill: world.lockpickingSkill,
            settings: settings,
            perks: perks
        )
        session = LockpickingSession(
            parameters: parameters,
            sweetSpotCenter: random.uniform(in: -parameters.halfArc ... parameters.halfArc),
            picks: picks,
            pickHealth: pickHealth,
            startingOffset: random.uniform(in: -1 ... 1)
        )
        sessionTarget = target
        sessionLock = LockpickingTarget(key: lock.key, state: lock.state, perks: perks)
        sessionExperience = 0
        lastAction = .picking(name: target.interaction.name, difficulty: difficulty)
    }

    private func perkValues(lock: ReferenceKey, level: UInt8) -> LockpickingPerkValues {
        func value(_ start: Float, _ point: PerkEntryPoint) -> Float {
            world.perkValue(start, at: point, lock: lock, level: level)
        }
        return LockpickingPerkValues(
            sweetSpotFactor: value(1, LockpickingEntryPoint.sweetSpot),
            startingArc: value(0, LockpickingEntryPoint.startingArc),
            unbreakable: value(0, LockpickingEntryPoint.unbreakable) > 0,
            keyRewardChance: value(0, LockpickingEntryPoint.keyReward),
            crimeChance: value(1, LockpickingEntryPoint.crimeChance)
        )
    }
}
