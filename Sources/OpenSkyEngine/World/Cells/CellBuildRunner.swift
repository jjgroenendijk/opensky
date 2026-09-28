// Off-main cell build execution (todo 3.2 async build): the serial-executor
// half of streaming. CellSceneProvider is the build seam (real builder in the
// app, a fake in unit tests); CellBuildRunning runs builds off the main thread
// and buffers their results for the main-thread streamer to poll once per
// frame. Concurrency confinement decision: docs/engine/cell-streaming.md.

import Foundation
import OpenSkyAudio
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyRendering
import OpenSkyWorldState

/// Builds one cell scene by grid coordinate. The single seam scene build
/// crosses to reach `CellSceneBuilder`; a fake conformer lets CellStreamer
/// tests run without Metal or game data. Called only on the runner's serial
/// executor (never the main thread), so it inherits the single-threaded
/// confinement CellSceneBuilder / MeshLibrary / TextureLibrary require.
nonisolated public protocol CellSceneProvider {
    /// Throws `CellSceneError.cellNotFound` for a void grid slot; any other
    /// throw is a build failure. Both are classified by the streamer.
    ///
    /// - Parameter state: the runtime world state to build against (issue
    ///   #160). It is an immutable value captured on the main thread, which is
    ///   the only way store state reaches this executor.
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
    /// MATT index (issue #358); nil on a synthetic scene, and then the footstep
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
    /// PACK records plus resolved NPC_ package lists (issue #201).
    public var packageStore: PackageStore?
    /// Item/container/leveled-list indexes (issue #177); nil when the session
    /// was built without them, which is every synthetic scene.
    public var inventoryBaselines: InventoryBaselineResolver?
    /// Equippable-item slot index (issue #178); nil on the same synthetic
    /// scenes, and then equipping reports itself unavailable.
    public var equipmentCatalog: EquipmentCatalog?
    /// RACE/CLAS/NPC_ stat indexes (issue #194); nil on the same synthetic
    /// scenes, and then actor values report themselves unavailable.
    public var actorValueBaselines: ActorValueBaselineResolver?
    /// Load-order MGEF index (issue #469); nil on the same synthetic scenes,
    /// and then active effects report themselves unavailable.
    public var magicEffectStore: MagicEffectStore?
    /// Plugin every magic item's EFID links are relative to (issue #469).
    public var magicItemPluginName: String?
    /// Load-order SPEL and SCRL index (issue #470); nil on the same synthetic
    /// scenes, and then the spellbook reports itself unavailable.
    public var spellStore: SpellStore?
    /// Load-order EQUP index (issue #470), which answers which hands a readied
    /// spell takes.
    public var equipSlotStore: EquipSlotStore?
    /// Load-order ENCH index (issue #472); nil on the same synthetic scenes, and
    /// then an enchanted item applies nothing and the readout says so.
    public var enchantmentStore: EnchantmentStore?
    /// Load-order PERK index (issue #497); nil on the same synthetic scenes,
    /// and then the perk runtime reports itself unavailable.
    public var perkStore: PerkStore?
    /// Load-order FACT index (issue #501); nil on the same synthetic scenes,
    /// and then every actor derives as neutral toward everyone.
    public var factionStore: FactionStore?
    /// Load-order RELA and ASTP index (issue #502); nil on the same synthetic
    /// scenes, and then no pair overrides its factions.
    public var relationshipStore: RelationshipStore?
    /// Load-order FLST index (issue #506); nil on the same synthetic scenes,
    /// and then vendors trade without their keyword lists.
    public var formListStore: FormListStore?
    /// Load-order AVIF index (issue #498); nil on the same synthetic scenes,
    /// and then skill advancement has no parameters and reports the drop.
    public var actorValueInformation: ActorValueInformationStore?
    /// GMST-derived skill-use curve and per-rank character experience (issue
    /// #498), defaulting to the documented numbers on a synthetic scene.
    public var skillAdvancementSettings: SkillAdvancementSettings = .documentedDefaults
    /// GMST-derived level curve and level-up rewards (issue #499), defaulting
    /// to the documented numbers on a synthetic scene.
    public var characterLevelSettings: CharacterLevelSettings = .documentedDefaults
    /// GMST-derived walk/run values plus explicit documented fallbacks.
    public var movementConfiguration: PlayerMovementConfiguration = .synthetic
    /// GMST-derived `fBarterMin` and `fBarterMax` at the milestone's fixed
    /// Speech value (issue #179), defaulting to the documented vanilla numbers.
    public var barterPricing: BarterPricing = .vanilla
    /// GMST-derived combat distance and block factors (issue #195),
    /// defaulting to the documented vanilla numbers on a synthetic scene.
    public var combatSettings: CombatSettings = .synthetic
    /// GMST-derived arrow tilt-up angles and visible-move distance (issue
    /// #196), defaulting to the UESP-documented numbers on a synthetic scene.
    public var archerySettings: ArcherySettings = .synthetic
    /// GMST-derived detection ranges, noise weights and thresholds (issue
    /// #202), defaulting to the documented numbers on a synthetic scene.
    public var detectionSettings: DetectionSettings = .synthetic

    /// Compiled-script source for the Papyrus world runtime; nil when the
    /// builder was constructed without a file system (synthetic scenes).
    public var scriptFileSystem: VirtualFileSystem? {
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
    public let totalDurationMS: Double

    public init(
        coordinate: CellCoordinate,
        result: Result<CellScene, any Error>,
        totalDurationMS: Double = 0
    ) {
        self.coordinate = coordinate
        self.result = result
        self.totalDurationMS = totalDurationMS
    }
}

nonisolated public struct CellBuildMetric: Equatable, Sendable {
    public let totalDurationMS: Double
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

/// Production runner: one serial `DispatchQueue` builds cells one at a time
/// (matching the 3.2 "build one at a time" budget) off the main thread. The
/// provider + its libraries are confined to this queue; the only shared state
/// is the tiny completion buffer, guarded by its own lock. That lock lives
/// here, not inside the libraries -- confinement keeps the caches lock-free.
nonisolated public final class SerialCellBuildRunner: CellBuildRunning, @unchecked Sendable {
    private let provider: any CellSceneProvider
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var completed: [CellBuildResult] = []
    /// Execution counts support streaming verification. Kept beside pending
    /// under the same lock so the fly-path gate can prove each desired cell
    /// built once, including completed results not drained yet.
    private var buildCounts: [CellCoordinate: Int] = [:]
    private var buildMetrics: [CellCoordinate: CellBuildMetric] = [:]
    /// Coordinates queued-or-building, so a duplicate enqueue is a no-op --
    /// defence in depth over the streamer's own dedup. Bounds the queue depth
    /// to the grid size regardless of caller bugs (guards the 30 GB runaway).
    private var pending: Set<CellCoordinate> = []
    private var pendingLOD: Set<CellCoordinate> = []
    private var completedLOD: [DistantLODBuildResult] = []
    private var pendingDoorTransitions: Set<FormID> = []
    private var completedDoorTransitions: [DoorTransitionBuildResult] = []

    public init(
        provider: any CellSceneProvider,
        label: String = "nl.jjgroenendijk.opensky.cellbuild"
    ) {
        self.provider = provider
        queue = DispatchQueue(label: label, qos: .utility)
    }

    public func enqueue(_ coordinate: CellCoordinate, state: WorldStateSnapshot) {
        lock.lock()
        let isNew = pending.insert(coordinate).inserted
        lock.unlock()
        guard isNew else { return }
        queue.async { [self] in
            lock.lock()
            buildCounts[coordinate, default: 0] += 1
            lock.unlock()
            let started = DispatchTime.now().uptimeNanoseconds
            let result = Result { try provider.buildCell(at: coordinate, state: state) }
            let duration = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
            let entry = CellBuildResult(
                coordinate: coordinate,
                result: result,
                totalDurationMS: duration
            )
            lock.lock()
            if case let .success(scene) = result {
                buildMetrics[coordinate] = CellBuildMetric(
                    totalDurationMS: duration,
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
            completed.append(entry)
            lock.unlock()
        }
    }

    public func drainCompleted() -> [CellBuildResult] {
        lock.lock()
        defer { lock.unlock() }
        let out = completed
        completed.removeAll(keepingCapacity: true)
        for entry in out {
            pending.remove(entry.coordinate)
        }
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
        lock.lock()
        let isNew = pendingLOD.insert(center).inserted
        lock.unlock()
        guard isNew else { return false }
        queue.async { [self] in
            let result = Result {
                try provider.buildDistantLOD(center: center, hiddenCells: hiddenCells)
            }
            lock.lock()
            completedLOD.append(DistantLODBuildResult(center: center, result: result))
            lock.unlock()
        }
        return true
    }

    public func drainCompletedDistantLOD() -> [DistantLODBuildResult] {
        lock.lock()
        defer { lock.unlock() }
        let out = completedLOD
        completedLOD.removeAll(keepingCapacity: true)
        for entry in out {
            pendingLOD.remove(entry.center)
        }
        return out
    }

    public func enqueueDoorTransition(from sourceDoor: FormID, state: WorldStateSnapshot) {
        lock.lock()
        let isNew = pendingDoorTransitions.insert(sourceDoor).inserted
        lock.unlock()
        guard isNew else { return }
        queue.async { [self] in
            let result = Result {
                try provider.buildDoorTransition(from: sourceDoor, state: state)
            }
            lock.lock()
            completedDoorTransitions.append(DoorTransitionBuildResult(
                sourceDoor: sourceDoor,
                result: result
            ))
            lock.unlock()
        }
    }

    public func drainCompletedDoorTransitions() -> [DoorTransitionBuildResult] {
        lock.lock()
        defer { lock.unlock() }
        let out = completedDoorTransitions
        completedDoorTransitions.removeAll(keepingCapacity: true)
        for entry in out {
            pendingDoorTransitions.remove(entry.sourceDoor)
        }
        return out
    }

    /// Thread-safe snapshot for tests + scripted streaming verification.
    public func buildCountsSnapshot() -> [CellCoordinate: Int] {
        lock.lock()
        defer { lock.unlock() }
        return buildCounts
    }

    public func buildMetricsSnapshot() -> [CellCoordinate: CellBuildMetric] {
        lock.lock()
        defer { lock.unlock() }
        return buildMetrics
    }
}
