public import OpenSkyAudio
public import OpenSkyFormatsESM
public import OpenSkyWorldInterface

/// What the world adapters use of `WorldMusicDirector`.
public protocol WorldMusicDirectorPort: AnyObject {
    @discardableResult func addScriptedMusic(_ id: FormID) -> MusicRefusal?
    func handleMusicContext(_ context: MusicContext)
    @discardableResult func playDiscoveryMusic(markerType: UInt8) -> MusicRefusal?
    @discardableResult func playSpecialMusic(_ kind: SpecialMusic) -> MusicRefusal?
    func removeScriptedMusic(_ id: FormID)
    @discardableResult func setCombatActive(_ active: Bool) -> MusicRefusal?
}
