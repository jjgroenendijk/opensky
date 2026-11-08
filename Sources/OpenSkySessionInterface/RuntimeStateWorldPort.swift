public import OpenSkyActorsInterface
public import OpenSkyConditions
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkySaveInterface

/// What the world adapters use of `RuntimeStateWorldAdapter`.
public protocol RuntimeStateWorldPort: AnyObject {
    func actorResolution() -> ActorStateResolution
    func addLiveSeams(to context: inout ConditionContext)
    func conditionData() -> ConditionDataResolution
    func deleteSave(slot: String) async throws
    func loadSession(slot: String) async throws
    func loadSession(slot: String, checksLoadOrder: Bool) async throws
    func saveListings() async throws -> [OpenSkySaveSlotListing]
    func saveSession(slot: String) async throws
    func saveSession(slot: String, summary: SaveSummary?, thumbnail: SaveThumbnail?) async throws
    func sessionContents(summary: SaveSummary?, thumbnail: SaveThumbnail?) -> OpenSkySaveContents
    func writeImported(_ contents: OpenSkySaveContents, slot: String) async throws
    func location(of scene: CellLocationKey) -> ResolvedFormID?
    func locationMusicType(of scene: CellLocationKey) -> FormID?
}
