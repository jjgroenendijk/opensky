// Off-main cell builds. `CellSceneProvider` is the build seam (the real builder
// in the app, a fake in unit tests); `CellBuildRunning` runs builds off the main
// thread and buffers results for the streamer to poll once per frame.

import Foundation
import OpenSkyAudio
import OpenSkyCombatInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyRendering
import OpenSkyWorldState
import os
import Synchronization

/// Builds one cell scene by grid coordinate. The single seam scene build
/// crosses to reach `CellSceneBuilder`; a fake conformer lets CellStreamer
/// tests run without Metal or game data. Called only on the runner's serial
/// executor (never the main thread), so it inherits the single-threaded
/// confinement CellSceneBuilder / MeshLibrary / TextureLibrary require.
nonisolated public protocol CellSceneProvider {
    /// Throws `CellSceneError.cellNotFound` for a void grid slot; any other throw is
    /// a build failure. The streamer classifies both.
    /// - Parameter state: the runtime world state to build against, an immutable
    ///   value captured on the main thread.
    func buildCell(at coordinate: CellCoordinate, state: WorldStateSnapshot) throws -> CellScene

    /// Drops the given cached assets (a departed cell's keys no resident cell
    /// needs). Runs on the same executor as builds so libraries stay confined.
    func evict(droppingMeshKeys: Set<String>, droppingTextureKeys: Set<String>)

    func buildDistantLOD(
        center: CellCoordinate,
        hiddenCells: Set<CellCoordinate>
    ) throws -> DistantLODScene?

    /// Resolves + builds the destination of one placed teleport door.
    func buildDoorTransition(
        from sourceDoor: FormID,
        state: WorldStateSnapshot
    ) throws -> DoorTransition
}

nonisolated extension CellSceneProvider {
    public func buildDistantLOD(
        center _: CellCoordinate,
        hiddenCells _: Set<CellCoordinate>
    ) throws -> DistantLODScene? {
        nil
    }

    public func buildDoorTransition(
        from sourceDoor: FormID,
        state _: WorldStateSnapshot
    ) throws -> DoorTransition {
        throw CellSceneError.doorReferenceNotFound(formID: sourceDoor)
    }
}

/// Adapts `CellSceneBuilder` to the provider seam, pinning the worldspace so
/// the streamer only passes grid coordinates. The builder + its libraries live
/// entirely on the runner's serial queue -- never touched from the main
/// thread -- which is why they need no internal locking.
nonisolated public struct BuilderCellSceneProvider: CellSceneProvider, WeatherProviding,
    AudioDataProviding, MovementConfigurationProviding, GlobalDataProviding,
    ScriptDataProviding, ItemDataProviding, BarterDataProviding, QuestDataProviding,
    LocationDataProviding, DialogueDataProviding, ActorValueDataProviding, CombatDataProviding,
    PackageDataProviding, MagicDataProviding, ProgressionDataProviding,
    FactionDataProviding
{
    public let builder: CellSceneBuilder
    public let worldspaceEditorID: String
    /// Weather runtime for this worldspace; nil when the plugin has no WTHR.
    public var weatherSystem: WeatherSystem?
    /// Sound record index (SOUN/SNDR); nil when the plugin has no sound data.
    public var soundStore: SoundRecordStore?
    /// Footstep index (FSTS/FSTP/IPDS/IPCT); nil when the session was built
    /// without one, which is every synthetic scene.
    public var footstepStore: FootstepStore?
    /// MATT index; nil on a synthetic scene, and then the footstep
    /// readout names a material by FormID.
    public var materialTypes: MaterialTypeIndex?
    /// Acoustic-space index (ASPC); nil when the plugin has no ASPC records.
    public var aspcStore: AcousticSpaceStore?
    /// Music record index (MUSC/MUST); nil when the plugin has no music data.
    public var musicStore: MusicRecordStore?
    /// Global-variable index (GLOB); nil when the plugin has no GLOB records.
    public var globalStore: GlobalStore?
    /// Quest index (QUST); nil when the plugin has no QUST records, and then
    /// every `Quest` native reports itself unavailable rather than guessing.
    public var questStore: QuestStore?
    /// LCTN/LCRT lookup for quest aliases and CELL location names.
    public var locationStore: LocationStore?
    /// Topic, response and voice-type records for the dialogue runtime.
    public var dialogueStore: DialogueStore?
    /// PACK records plus resolved NPC_ package lists.
    public var packageStore: PackageStore?
    /// Item/container/leveled-list indexes; nil when the session
    /// was built without them, which is every synthetic scene.
    public var inventoryBaselines: InventoryBaselineResolver?
    /// Equippable-item slot index; nil on the same synthetic
    /// scenes, and then equipping reports itself unavailable.
    public var equipmentCatalog: EquipmentCatalog?
    /// RACE/CLAS/NPC_ stat indexes; nil on the same synthetic
    /// scenes, and then actor values report themselves unavailable.
    public var actorValueBaselines: ActorValueBaselineResolver?
    /// Load-order MGEF index; nil on the same synthetic scenes,
    /// and then active effects report themselves unavailable.
    public var magicEffectStore: MagicEffectStore?
    /// Plugin every magic item's EFID links are relative to.
    public var magicItemPluginName: String?
    /// Load-order SPEL and SCRL index; nil on the same synthetic
    /// scenes, and then the spellbook reports itself unavailable.
    public var spellStore: SpellStore?
    /// Load-order EQUP index, which answers which hands a readied
    /// spell takes.
    public var equipSlotStore: EquipSlotStore?
    /// Load-order ENCH index; nil on the same synthetic scenes, and
    /// then an enchanted item applies nothing and the readout says so.
    public var enchantmentStore: EnchantmentStore?
    /// Load-order PERK index; nil on the same synthetic scenes,
    /// and then the perk runtime reports itself unavailable.
    public var perkStore: PerkStore?
    /// Load-order FACT index; nil on the same synthetic scenes,
    /// and then every actor derives as neutral toward everyone.
    public var factionStore: FactionStore?
    /// Load-order RELA and ASTP index; nil on the same synthetic
    /// scenes, and then no pair overrides its factions.
    public var relationshipStore: RelationshipStore?
    /// Load-order FLST index; nil on the same synthetic scenes,
    /// and then vendors trade without their keyword lists.
    public var formListStore: FormListStore?
    /// Load-order AVIF index; nil on the same synthetic scenes,
    /// and then skill advancement has no parameters and reports the drop.
    public var actorValueInformation: ActorValueInformationStore?
    /// GMST-derived skill-use curve and per-rank character experience, defaulting to
    /// the documented numbers on a synthetic scene.
    public var skillAdvancementSettings: SkillAdvancementSettings = .documentedDefaults
    /// GMST-derived level curve and level-up rewards, defaulting
    /// to the documented numbers on a synthetic scene.
    public var characterLevelSettings: CharacterLevelSettings = .documentedDefaults
    /// GMST-derived walk/run values plus explicit documented fallbacks.
    public var movementConfiguration: PlayerMovementConfiguration = .synthetic
    /// GMST-derived `fBarterMin` and `fBarterMax` at the milestone's fixed
    /// Speech value, defaulting to the documented vanilla numbers.
    public var barterPricing: BarterPricing = .vanilla
    /// GMST-derived combat distance and block factors,
    /// defaulting to the documented vanilla numbers on a synthetic scene.
    public var combatSettings: CombatSettings = .synthetic
    /// GMST-derived arrow tilt-up angles and visible-move distance, defaulting to the
    /// UESP-documented numbers on a synthetic scene.
    public var archerySettings: ArcherySettings = .synthetic
    /// GMST-derived detection ranges, noise weights, and thresholds, defaulting to
    /// the documented numbers on a synthetic scene.
    public var detectionSettings: DetectionSettings = .synthetic

    /// Compiled-script source for the Papyrus world runtime; nil when the
    /// builder was constructed without a file system (synthetic scenes).
    public var scriptFileSystem: (any GameFileSource)? {
        builder.fileSystem
    }

    /// The same master-list resolver every streamed reference key came from.
    public var scriptFormIDResolver: FormIDResolver {
        builder.formIDResolver
    }

    public func buildCell(
        at coordinate: CellCoordinate,
        state: WorldStateSnapshot
    ) throws -> CellScene {
        try builder.buildScene(
            worldspaceEditorID: worldspaceEditorID,
            gridX: coordinate.x,
            gridY: coordinate.y,
            state: state
        )
    }

    public func evict(
        droppingMeshKeys meshKeys: Set<String>,
        droppingTextureKeys textureKeys: Set<String>
    ) {
        builder.meshes.evict(dropping: meshKeys)
        builder.collisionModels?.evict(dropping: meshKeys)
        builder.evictCollisionPartitions(dropping: meshKeys)
        builder.textures.evict(dropping: textureKeys)
    }

    public func buildDistantLOD(
        center: CellCoordinate,
        hiddenCells: Set<CellCoordinate>
    ) throws -> DistantLODScene? {
        try builder.buildDistantLOD(
            worldspaceEditorID: worldspaceEditorID,
            center: center,
            hiddenCells: hiddenCells
        )
    }

    public func buildDoorTransition(
        from sourceDoor: FormID,
        state: WorldStateSnapshot
    ) throws -> DoorTransition {
        try builder.buildDoorTransition(
            from: sourceDoor,
            worldspaceEditorID: worldspaceEditorID,
            state: state
        )
    }

    public init(
        builder: CellSceneBuilder,
        worldspaceEditorID: String,
        weatherSystem: WeatherSystem? = nil,
        soundStore: SoundRecordStore? = nil,
        footstepStore: FootstepStore? = nil,
        materialTypes: MaterialTypeIndex? = nil,
        aspcStore: AcousticSpaceStore? = nil,
        musicStore: MusicRecordStore? = nil,
        globalStore: GlobalStore? = nil,
        questStore: QuestStore? = nil,
        locationStore: LocationStore? = nil,
        dialogueStore: DialogueStore? = nil,
        packageStore: PackageStore? = nil,
        inventoryBaselines: InventoryBaselineResolver? = nil,
        equipmentCatalog: EquipmentCatalog? = nil,
        actorValueBaselines: ActorValueBaselineResolver? = nil,
        magicEffectStore: MagicEffectStore? = nil,
        magicItemPluginName: String? = nil,
        spellStore: SpellStore? = nil,
        equipSlotStore: EquipSlotStore? = nil,
        enchantmentStore: EnchantmentStore? = nil,
        perkStore: PerkStore? = nil,
        factionStore: FactionStore? = nil,
        relationshipStore: RelationshipStore? = nil,
        formListStore: FormListStore? = nil,
        actorValueInformation: ActorValueInformationStore? = nil,
        skillAdvancementSettings: SkillAdvancementSettings = .documentedDefaults,
        characterLevelSettings: CharacterLevelSettings = .documentedDefaults,
        movementConfiguration: PlayerMovementConfiguration = .synthetic,
        barterPricing: BarterPricing = .vanilla,
        combatSettings: CombatSettings = .synthetic,
        archerySettings: ArcherySettings = .synthetic,
        detectionSettings: DetectionSettings = .synthetic
    ) {
        self.builder = builder
        self.worldspaceEditorID = worldspaceEditorID
        self.weatherSystem = weatherSystem
        self.soundStore = soundStore
        self.footstepStore = footstepStore
        self.materialTypes = materialTypes
        self.aspcStore = aspcStore
        self.musicStore = musicStore
        self.globalStore = globalStore
        self.questStore = questStore
        self.locationStore = locationStore
        self.dialogueStore = dialogueStore
        self.packageStore = packageStore
        self.inventoryBaselines = inventoryBaselines
        self.equipmentCatalog = equipmentCatalog
        self.actorValueBaselines = actorValueBaselines
        self.magicEffectStore = magicEffectStore
        self.magicItemPluginName = magicItemPluginName
        self.spellStore = spellStore
        self.equipSlotStore = equipSlotStore
        self.enchantmentStore = enchantmentStore
        self.perkStore = perkStore
        self.factionStore = factionStore
        self.relationshipStore = relationshipStore
        self.formListStore = formListStore
        self.actorValueInformation = actorValueInformation
        self.skillAdvancementSettings = skillAdvancementSettings
        self.characterLevelSettings = characterLevelSettings
        self.movementConfiguration = movementConfiguration
        self.barterPricing = barterPricing
        self.combatSettings = combatSettings
        self.archerySettings = archerySettings
        self.detectionSettings = detectionSettings
    }
}

/// One finished build handed back to the main-thread streamer.
nonisolated public struct CellBuildResult {
    public let coordinate: CellCoordinate
    public let result: Result<CellScene, any Error>

    public init(
        coordinate: CellCoordinate,
        result: Result<CellScene, any Error>
    ) {
        self.coordinate = coordinate
        self.result = result
    }
}

nonisolated public struct CellBuildMetric: Equatable, Sendable {
    public let collisionDurationMS: Double
    public let collisionShapeCount: Int
    public let collisionTriangleCount: Int
    /// Actor phase accounting mirrored off CellLoadSummary so the fly bench
    /// can gate latency + exact accounting per cell (5.5).
    public var actorDurationMS = 0.0
    public var actorDiscoveredCount = 0
    public var actorRenderedCount = 0
    public var actorDisabledSkipCount = 0
    public var actorFailureCount = 0
    /// One reason per counted failure, mirrored off CellLoadSummary so the
    /// fly bench can prove every failure explained (5.6 acceptance).
    public var actorFailureReasons: [String] = []
    public var actorAnimatedCount = 0
    public var actorAnimationFailureCount = 0
    public var actorAnimationFailureReasons: [String] = []

    public var actorAccountingIsExact: Bool {
        actorDiscoveredCount
            == actorRenderedCount + actorDisabledSkipCount + actorFailureCount
    }

    public var actorFailuresAreExplained: Bool {
        actorFailureCount == actorFailureReasons.count
    }

    public var actorAnimationAccountingIsExact: Bool {
        actorRenderedCount == actorAnimatedCount + actorAnimationFailureCount
    }

    public var actorAnimationFailuresAreExplained: Bool {
        actorAnimationFailureCount == actorAnimationFailureReasons.count
    }
}

nonisolated public struct DistantLODBuildResult {
    public let center: CellCoordinate
    public let result: Result<DistantLODScene?, any Error>
}

nonisolated public struct DoorTransitionBuildResult {
    public let sourceDoor: FormID
    public let result: Result<DoorTransition, any Error>
}

/// Runs cell builds off the main thread and buffers the results for a
/// main-thread poll. The streamer enqueues coordinates and drains completions
/// once per frame; ordering of completions is the executor's business.
nonisolated public protocol CellBuildRunning: AnyObject {
    /// - Parameter state: the world-state snapshot the build runs against,
    ///   captured by the caller before the work leaves the main thread.
    func enqueue(_ coordinate: CellCoordinate, state: WorldStateSnapshot)
    /// Returns and clears everything finished since the last drain.
    func drainCompleted() -> [CellBuildResult]
    /// Schedules an eviction pass on the build executor (after queued builds),
    /// dropping the given assets a departed cell no longer needs.
    func enqueueEviction(droppingMeshKeys: Set<String>, droppingTextureKeys: Set<String>)
    @discardableResult
    func enqueueDistantLOD(center: CellCoordinate, hiddenCells: Set<CellCoordinate>) -> Bool
    func drainCompletedDistantLOD() -> [DistantLODBuildResult]
    func enqueueDoorTransition(from sourceDoor: FormID, state: WorldStateSnapshot)
    func drainCompletedDoorTransitions() -> [DoorTransitionBuildResult]
}

nonisolated extension CellBuildRunning {
    @discardableResult
    public func enqueueDistantLOD(
        center _: CellCoordinate,
        hiddenCells _: Set<CellCoordinate>
    ) -> Bool {
        false
    }

    public func drainCompletedDistantLOD() -> [DistantLODBuildResult] {
        []
    }

    public func enqueueDoorTransition(from _: FormID, state _: WorldStateSnapshot) {}
    public func drainCompletedDoorTransitions() -> [DoorTransitionBuildResult] {
        []
    }
}

/// Builds cells one at a time on one serial queue, off the main thread.
/// Unchecked `Sendable`: the provider and its scenes are not `Sendable`; they stay
/// on `queue` until `results` hands a scene over (docs/engine/cell-streaming.md).
nonisolated public final class SerialCellBuildRunner: CellBuildRunning, @unchecked Sendable {
    nonisolated private struct Bookkeeping {
        /// Lets the fly-path gate prove each wanted cell built once.
        var buildCounts: [CellCoordinate: Int] = [:]
        var buildMetrics: [CellCoordinate: CellBuildMetric] = [:]
        /// Queued or building. A duplicate enqueue is a no-op, which bounds the
        /// queue depth to the grid size even if the streamer has a bug.
        var pending: Set<CellCoordinate> = []
        var pendingLOD: Set<CellCoordinate> = []
        var pendingDoorTransitions: Set<FormID> = []
    }

    nonisolated private struct Results {
        var cells: [CellBuildResult] = []
        var distantLOD: [DistantLODBuildResult] = []
        var doorTransitions: [DoorTransitionBuildResult] = []
    }

    private let provider: any CellSceneProvider
    private let queue: DispatchQueue
    private let bookkeeping = Mutex(Bookkeeping())
    /// Holds scenes, which are not `Sendable`, so the compiler cannot check it.
    private let results = OSAllocatedUnfairLock(uncheckedState: Results())

    public init(
        provider: any CellSceneProvider,
        label: String = "nl.jjgroenendijk.opensky.cellbuild"
    ) {
        self.provider = provider
        queue = DispatchQueue(label: label, qos: .utility)
    }

    public func enqueue(_ coordinate: CellCoordinate, state: WorldStateSnapshot) {
        let isNew = bookkeeping.withLock { $0.pending.insert(coordinate).inserted }
        guard isNew else { return }
        queue.async { [self] in
            bookkeeping.withLock { $0.buildCounts[coordinate, default: 0] += 1 }
            let result = Result { try provider.buildCell(at: coordinate, state: state) }
            if let metric = try? result.map(Self.metric(for:)).get() {
                bookkeeping.withLock { $0.buildMetrics[coordinate] = metric }
            }
            let entry = CellBuildResult(coordinate: coordinate, result: result)
            results.withLockUnchecked { $0.cells.append(entry) }
        }
    }

    private static func metric(for scene: CellScene) -> CellBuildMetric {
        CellBuildMetric(
            collisionDurationMS: scene.staticCollision.buildDurationMS,
            collisionShapeCount: scene.staticCollision.stats.shapeCount,
            collisionTriangleCount: scene.staticCollision.stats.triangleCount,
            actorDurationMS: scene.summary.actorBuildDurationMS,
            actorDiscoveredCount: scene.summary.actorCount,
            actorRenderedCount: scene.summary.actorDrawnCount,
            actorDisabledSkipCount: scene.summary.actorDisabledSkipCount,
            actorFailureCount: scene.summary.actorFailureCount,
            actorFailureReasons: scene.summary.actorFailureReasons,
            actorAnimatedCount: scene.summary.actorAnimatedCount,
            actorAnimationFailureCount: scene.summary.actorAnimationFailureCount,
            actorAnimationFailureReasons: scene.summary.actorAnimationFailureReasons
        )
    }

    public func drainCompleted() -> [CellBuildResult] {
        let out = results.withLockUnchecked {
            defer { $0.cells.removeAll(keepingCapacity: true) }
            return $0.cells
        }
        bookkeeping.withLock { $0.pending.subtract(out.map(\.coordinate)) }
        return out
    }

    public func enqueueEviction(
        droppingMeshKeys meshKeys: Set<String>,
        droppingTextureKeys textureKeys: Set<String>
    ) {
        guard !meshKeys.isEmpty || !textureKeys.isEmpty else { return }
        queue.async { [self] in
            provider.evict(droppingMeshKeys: meshKeys, droppingTextureKeys: textureKeys)
        }
    }

    @discardableResult
    public func enqueueDistantLOD(
        center: CellCoordinate,
        hiddenCells: Set<CellCoordinate>
    ) -> Bool {
        let isNew = bookkeeping.withLock { $0.pendingLOD.insert(center).inserted }
        guard isNew else { return false }
        queue.async { [self] in
            let result = Result {
                try provider.buildDistantLOD(center: center, hiddenCells: hiddenCells)
            }
            let entry = DistantLODBuildResult(center: center, result: result)
            results.withLockUnchecked { $0.distantLOD.append(entry) }
        }
        return true
    }

    public func drainCompletedDistantLOD() -> [DistantLODBuildResult] {
        let out = results.withLockUnchecked {
            defer { $0.distantLOD.removeAll(keepingCapacity: true) }
            return $0.distantLOD
        }
        bookkeeping.withLock { $0.pendingLOD.subtract(out.map(\.center)) }
        return out
    }

    public func enqueueDoorTransition(from sourceDoor: FormID, state: WorldStateSnapshot) {
        let isNew = bookkeeping.withLock { $0.pendingDoorTransitions.insert(sourceDoor).inserted }
        guard isNew else { return }
        queue.async { [self] in
            let result = Result {
                try provider.buildDoorTransition(from: sourceDoor, state: state)
            }
            let entry = DoorTransitionBuildResult(sourceDoor: sourceDoor, result: result)
            results.withLockUnchecked { $0.doorTransitions.append(entry) }
        }
    }

    public func drainCompletedDoorTransitions() -> [DoorTransitionBuildResult] {
        let out = results.withLockUnchecked {
            defer { $0.doorTransitions.removeAll(keepingCapacity: true) }
            return $0.doorTransitions
        }
        bookkeeping.withLock { $0.pendingDoorTransitions.subtract(out.map(\.sourceDoor)) }
        return out
    }

    /// Thread-safe snapshot for tests and scripted streaming checks.
    public func buildCountsSnapshot() -> [CellCoordinate: Int] {
        bookkeeping.withLock { $0.buildCounts }
    }

    public func buildMetricsSnapshot() -> [CellCoordinate: CellBuildMetric] {
        bookkeeping.withLock { $0.buildMetrics }
    }

    /// Blocks until every job queued so far has run. Tests use it instead of
    /// a fixed sleep. Never call it on the build queue.
    public func waitUntilIdle() {
        queue.sync {}
    }
}
