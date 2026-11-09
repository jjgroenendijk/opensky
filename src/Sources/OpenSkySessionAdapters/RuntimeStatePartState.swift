import OpenSkyCells
import OpenSkyGameData
import OpenSkySave
import OpenSkyWorldInterface

/// What `RuntimeStateWorldAdapter` and its parts keep between reads.
public final class RuntimeStatePartState {
    /// Resolved once: retrying an unwritable Application Support on every
    /// readout tick would hit the disk for the same answer.
    var saveStore: OpenSkySaveStore?
    /// Parses every plugin header, so it is built once per session.
    var fingerprint: Task<[SavePluginFingerprint], any Error>?
    /// Built once, the first time a condition asks where something is.
    var cellLocations: CellLocationResolver?
    /// Reference places for one set of resident cells, rebuilt when the set changes.
    var referencePlaces: ResidentReferencePlaces?
    /// Condition views kept until their inputs change.
    public let conditionCaches = ConditionViewCaches()

    public init() {}
}

/// Where resident references are, for one set of resident cells and reference count.
struct ResidentReferencePlaces {
    let cells: Set<CellSceneLocation>
    let count: Int
    let places: ReferencePlaces
}
