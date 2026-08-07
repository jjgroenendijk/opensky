// Optional capability seams a `CellSceneProvider` can also conform to.
//
// A satellite of `CellBuildRunner.swift`, which sits at the strict file-length
// cap. These belong together rather than beside their own subsystems: every one
// of them answers the same question — what a provider built from real plugin
// data can hand the main thread that a synthetic scene cannot — and
// `GameViewController` reaches for them in one place, at session wire-up.
//
// Every value behind these is immutable after `init`, which is what makes
// reading one from the main thread safe while the builder itself stays confined
// to its serial queue.

import Foundation

/// Optional weather runtime a provider can expose (M7.2.2). GameViewController
/// pulls it off the provider to hand the renderer. Built once at setup from the
/// same ESM data, then read-only value types — safe to share to the main thread.
nonisolated protocol WeatherProviding {
    var weatherSystem: WeatherSystem? { get }
}

/// Optional GLOB index a provider can expose (issue #165). GameViewController
/// pairs it with the session's `WorldStateStore` to build the
/// `GlobalResolution` conditions, the clock and weather-chance selection read
/// global values through.
nonisolated protocol GlobalDataProviding {
    var globalStore: GlobalStore? { get }
}

/// Optional QUST index a provider can expose (issue #322). `GameViewController`
/// pairs it with the session's `WorldStateStore` to build the `QuestRuntime`
/// the `Quest` natives mutate and the quest script instances are started from.
/// Immutable after `init` like every other `*Store` here.
nonisolated protocol QuestDataProviding {
    var questStore: QuestStore? { get }
}

/// Optional item + container indexes a provider can expose (issue #177).
/// `GameViewController` pairs the resolver with the session's
/// `WorldStateStore` to build the `InventoryRuntime` that take, drop and
/// container sessions run on. Immutable after `init` like every other `*Store`
/// here, so reading it from the main thread does not break the builder's queue
/// confinement.
nonisolated protocol ItemDataProviding {
    var inventoryBaselines: InventoryBaselineResolver? { get }
    /// Slot and model data for equippable items (issue #178), paired with the
    /// baselines above to build the session's `EquipmentRuntime`. Separate
    /// from the baseline resolver because equipping needs body templates the
    /// inventory view deliberately does not carry.
    var equipmentCatalog: EquipmentCatalog? { get }
}

/// Optional RACE/CLAS/NPC_ stat indexes a provider can expose (issue #194).
/// `GameViewController` pairs the resolver with the session's `WorldStateStore`
/// to build the `ActorValueRuntime` that damage, restore and regeneration run
/// on. Immutable after `init` like every other `*Resolver` here, so reading it
/// from the main thread does not break the builder's queue confinement.
nonisolated protocol ActorValueDataProviding {
    var actorValueBaselines: ActorValueBaselineResolver? { get }
}

/// Optional script-loading seam a provider can expose (issue #171). The
/// Papyrus world runtime resolves a script name to compiled bytecode lazily
/// through the file system, and resolves the FormIDs a VMAD property names
/// with the same master table the cell build used, so a script and the cell
/// it is attached to agree on reference identity.
///
/// Both values are immutable and thread-safe (`VirtualFileSystem` is
/// `Sendable`; `FormIDResolver` is a value), so reading them from the main
/// thread does not break the builder's queue confinement.
nonisolated protocol ScriptDataProviding {
    var scriptFileSystem: VirtualFileSystem? { get }
    var scriptFormIDResolver: FormIDResolver { get }
}

/// Optional immutable player-movement tuning resolved from active GMST data.
nonisolated protocol MovementConfigurationProviding {
    var movementConfiguration: PlayerMovementConfiguration { get }
}

/// Optional barter price factors resolved from active GMST data (issue #179).
/// Separate from `MovementConfigurationProviding` for the same reason the item
/// indexes are separate from the audio ones: a synthetic scene has no load
/// order to read `fBarterMin` and `fBarterMax` out of, and the merchant menu
/// then falls back to the documented vanilla defaults rather than to nothing.
nonisolated protocol BarterDataProviding {
    var barterPricing: BarterPricing { get }
}

/// Optional combat GMSTs resolved from active game data (issue #195).
///
/// Separate from `MovementConfigurationProviding` for the same reason
/// `BarterDataProviding` is: a synthetic scene has no load order to read
/// `fCombatDistance` and the block settings out of, and melee then falls back
/// to the UESP-documented numbers rather than to nothing.
nonisolated protocol CombatDataProviding {
    var combatSettings: CombatSettings { get }
}

/// Optional decoded audio-record stores a provider can expose (M9.2.2).
/// GameViewController pulls these off the provider to construct the world
/// sound director alongside the audio engine. WeatherStore arrives via
/// `WeatherProviding.weatherSystem?.store`.
nonisolated protocol AudioDataProviding {
    var soundStore: SoundRecordStore? { get }
    var aspcStore: AcousticSpaceStore? { get }
    /// Footstep record index (FSTS/FSTP/IPDS/IPCT), added in issue #352 for
    /// the footstep director.
    var footstepStore: FootstepStore? { get }
    /// Music record index (MUSC/MUST), added in M9.2.3 for the music director.
    var musicStore: MusicRecordStore? { get }
    /// MATT index (issue #358), so the footstep readout can name the surface
    /// the ground contact reported rather than print a bare FormID.
    var materialTypes: MaterialTypeIndex? { get }
}
