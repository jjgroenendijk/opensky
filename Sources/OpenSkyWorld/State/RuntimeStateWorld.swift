import OpenSkyAudio
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyWorldState

/// What `RuntimeStateCoordinator` reads from the live session. Saves go
/// through here because `OpenSkyWorld` may not import `OpenSkySave`.
@MainActor
public protocol RuntimeStateWorld: AnyObject {
    var residentReferenceCount: Int { get }
    func referenceEntry(formID: FormID) -> RuntimeReferenceEntry?
    /// The reference under the crosshair, nil when nothing is targeted.
    var crosshairReference: FormID? { get }

    /// Nil without a renderer.
    var gameClock: GameClock? { get set }
    var timescale: Float? { get }
    var isWorldSimPaused: Bool { get }
    /// Moves the renderer's hour directly, for a session with no globals.
    func setTimeOfDay(_ hour: Float)
    /// Seeds the next launch's clock.
    func persistTimeOfDay(_ hour: Float)
    /// Writes one time global into the clock and returns its previous value.
    func projectTimeGlobal(_ global: GameClock.TimeGlobal, value: Float) -> Float?
    /// Hands weather and the clock fresh global values.
    func applyGlobalResolution(_ resolution: GlobalResolution, reroll: Bool)

    var musicStore: MusicRecordStore? { get }
    /// The live condition context, with the crosshair as subject and target.
    func conditionContext(
        crosshair: RuntimeReferenceEntry?, globals: GlobalResolution
    ) -> ConditionContext

    /// The file work runs off the main actor. The state is read before the first
    /// await and a loaded save is applied after the last one, each in one frame.
    func saveSlots() async throws -> [String]
    func saveSession(slot: String) async throws
    func loadSession(slot: String) async throws
}
