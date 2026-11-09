// The record stores the combat, effects, and ragdoll adapters read. A port, so a test
// host can pass them without the whole world data.

public import OpenSkyAudio
public import OpenSkyGameData
public import OpenSkyInventoryInterface

/// The loaded records and tuning a combat adapter reads.
nonisolated public protocol CombatRecordsPort: WorldRecordsPort {
    var scriptFileSystem: (any GameFileSource)? { get }
    var footstepStore: FootstepStore? { get }
    var soundStore: SoundRecordStore? { get }
    var actorValueBaselines: ActorValueBaselineResolver? { get }
    var presentationRecords: PresentationRecordStore? { get }
    var inventoryBaselines: InventoryBaselineResolver? { get }
    var effectRecords: EffectRecordStore? { get }
    var combatSettings: CombatSettings { get }
    var archerySettings: ArcherySettings { get }
    var difficultySettings: DifficultySettings { get }
}
