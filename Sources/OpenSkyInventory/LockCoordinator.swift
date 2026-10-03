// The shell around `LockCore` and `LockpickingSession`: lock state in the world
// store, keys and lockpicks in the inventory, perks and skill use through the port.
// See docs/engine/locks.md.

import Foundation
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
    /// A lock changed, so the crosshair prompt may read differently.
    func lockStateChanged()
    /// The doors and containers with `XLOC` in the loaded cells.
    func lockables() -> [PlacedInteraction]
    /// An item's display name, for the key a lock names.
    func itemName(_ item: FormID) -> String
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
    public static let sweetSpot = PerkEntryPoint(rawValue: 59)
    public static let startingArc = PerkEntryPoint(rawValue: 63)
    public static let unbreakable = PerkEntryPoint(rawValue: 65)
    public static let keyReward = PerkEntryPoint(rawValue: 90)
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
    /// The `LKPK` default object. Nil keeps every lock shut to picking.
    public var lockpickItem: FormID?
    /// Sidebar override: treat the player as carrying every lock's key.
    public var playerCarriesEveryKey = false
    public var random = LockpickingRandom(seed: 0x4F_7065_6E53_6B79)
    public weak var world: (any LockWorld)?
    /// Health of the pick in hand. UESP: it carries over between locks.
    public internal(set) var pickHealth: Float = 1
    public internal(set) var session: LockpickingSession?
    public internal(set) var sessionTarget: InteractionTarget?
    var sessionLock: LockpickingTarget?
    var sessionExperience: Float = 0
    public internal(set) var lastOutcome: LockpickingOutcome?
    public internal(set) var lastText = "No lock action yet."
    /// The lock the sidebar works on.
    public var selectedLock: FormID?

    public init() {}

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

    /// The use-key gate. A carried key unlocks the target and lets the press through.
    public func gate(_ target: InteractionTarget) -> ActivationRefusal? {
        guard let lock = lock(of: target.interaction) else { return nil }
        switch LockCore.decide(lock: lock.state, carriesKey: carriesKey(lock.state.key)) {
        case .proceed:
            return nil
        case .unlockWithKey:
            write(lock.state, locked: false, for: lock.key)
            lastText = "Unlocked \(target.interaction.name) with its key."
            return nil
        case let .refuse(refusal):
            lastText = "\(target.interaction.name) is locked (\(lock.state.difficulty.name))."
            return refusal
        }
    }

    public func labelled(_ interaction: PlacedInteraction) -> PlacedInteraction {
        LockCore.labelled(interaction, lock: lock(of: interaction)?.state)
    }

    /// Forces the lock open or shut. The level and key stay as they are.
    @discardableResult
    public func setLocked(_ interaction: PlacedInteraction, locked: Bool) -> String {
        guard let lock = lock(of: interaction) else {
            return note("\(interaction.name) has no lock.")
        }
        write(lock.state, locked: locked, for: lock.key)
        return note("\(locked ? "Locked" : "Unlocked") \(interaction.name).")
    }

    func write(_ state: ReferenceLockState, locked: Bool, for key: ReferenceKey) {
        guard let items else { return }
        var updated = state
        updated.isLocked = locked
        items.store.set(updated, for: key, in: items.references?.cellLocation(of: key))
        world?.lockStateChanged()
    }

    @discardableResult
    public func note(_ text: String) -> String {
        lastText = text
        return text
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
        let difficulty = lock.state.difficulty
        guard difficulty.isPickable else { throw .requiresKey }
        let picks = lockpickCount
        guard picks > 0 else { throw .noLockpicks }
        let perks = perkValues(lock: lock.key, level: lock.state.level)
        let parameters = LockpickingParameters.make(
            difficulty: difficulty,
            skill: world?.lockpickingSkill ?? 0,
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
        lastText = "Picking \(target.interaction.name) (\(difficulty.name))."
    }

    private func perkValues(lock: ReferenceKey, level: UInt8) -> LockpickingPerkValues {
        guard let world else { return .none }
        func value(_ start: Float, _ point: PerkEntryPoint) -> Float {
            world.perkValue(start, at: point, lock: lock, level: level)
        }
        return LockpickingPerkValues(
            sweetSpotFactor: value(1, LockpickingEntryPoint.sweetSpot),
            startingArc: value(0, LockpickingEntryPoint.startingArc),
            unbreakable: value(0, LockpickingEntryPoint.unbreakable) > 0,
            keyRewardChance: value(0, LockpickingEntryPoint.keyReward)
        )
    }
}
