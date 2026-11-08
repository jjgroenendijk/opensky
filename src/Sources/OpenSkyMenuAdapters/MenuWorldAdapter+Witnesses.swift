public import OpenSkyActorsInterface
public import OpenSkyAgentControl
import OpenSkyAudio
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyInventory
import OpenSkyLaunch
import OpenSkyLoading
import OpenSkyMagic
public import OpenSkyMenus
public import OpenSkyMenusInterface
import OpenSkyPlayer
import OpenSkyProgression
public import OpenSkyProgressionInterface
public import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkySave
public import OpenSkySaveInterface
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// Witnesses that forward to the narrow parts of `MenuWorldAdapter`.
extension MenuWorldAdapter {
    public func applyAudioEnabled(_ enabled: Bool) {
        settingsApply.applyAudioEnabled(enabled)
    }

    public func applyMasterVolume(_ volume: Float) {
        settingsApply.applyMasterVolume(volume)
    }

    public func applyCategoryVolume(_ volume: Float, soundCategoryEditorID: String) {
        settingsApply.applyCategoryVolume(volume, soundCategoryEditorID: soundCategoryEditorID)
    }

    public func applyLook(sensitivity: Float, inverted: Bool) {
        settingsApply.applyLook(sensitivity: sensitivity, inverted: inverted)
    }

    public func applyHUD(_ hud: PlayerHUDSettings) {
        settingsApply.applyHUD(hud)
    }

    public func applyDifficulty(index: Int) {
        settingsApply.applyDifficulty(index: index)
    }

    public func applyBindings(_ bindings: InputBindings) {
        settingsApply.applyBindings(bindings)
    }

    public var skillsMenuSource: (any SkillsMenuSource)? {
        skillsRace.skillsMenuSource
    }

    public var menuInputConsumer: (any MenuInputConsumer)? {
        skillsRace.menuInputConsumer
    }

    public var isPlayerInBeastForm: Bool {
        skillsRace.isPlayerInBeastForm
    }

    public func playLevelUpMusic() {
        skillsRace.playLevelUpMusic()
    }

    public var skillsMenuTexts: GameSettingTexts<SkillsMenuText> {
        skillsRace.skillsMenuTexts
    }

    public var perkSkySource: PerkSkySource? {
        skillsRace.perkSkySource
    }

    public var perkSkySettings: PerkSkySettings {
        skillsRace.perkSkySettings
    }

    public var renderer: (any RendererPort)? {
        skillsRace.renderer
    }

    public var gameFiles: (any GameFileSource)? {
        skillsRace.gameFiles
    }

    public var viewCamera: FreeFlyCamera? {
        skillsRace.viewCamera
    }

    public var uiScene: UIScene {
        get { skillsRace.uiScene }
        set { skillsRace.uiScene = newValue }
    }

    public var playerIdentity: PlayerIdentityState? {
        skillsRace.playerIdentity
    }

    public var playableRaces: [RaceChoice] {
        skillsRace.playableRaces
    }

    public var raceMenuLabels: RaceMenuLabels {
        skillsRace.raceMenuLabels
    }

    public func raceMenuOptions(race: FormID, isFemale: Bool) -> RaceMenuOptions {
        skillsRace.raceMenuOptions(race: race, isFemale: isFemale)
    }

    public func applyPlayerIdentity(_ identity: PlayerIdentityState) {
        skillsRace.applyPlayerIdentity(identity)
    }

    public func racePresets(race: FormID, isFemale: Bool) -> [RacePreset] {
        skillsRace.racePresets(race: race, isFemale: isFemale)
    }

    public func raceMenuClosed() {
        skillsRace.raceMenuClosed()
    }

    public func startNewGame(at start: NewGameStart) {
        newGame.startNewGame(at: start)
    }

    public func holdWorldLoading() {
        newGame.holdWorldLoading()
    }

    public func quitApplication() {
        newGame.quitApplication()
    }

    public func showRaceMenu(limited: Bool) {
        scriptMenus.showRaceMenu(limited: limited)
    }

    public func fastTravel(to marker: ReferenceKey) -> Bool {
        scriptMenus.fastTravel(to: marker)
    }

    public func setFastTravelEnabled(_ enabled: Bool) {
        scriptMenus.setFastTravelEnabled(enabled)
    }

    public func setHUDCartMode(_ enabled: Bool) {
        scriptMenus.setHUDCartMode(enabled)
    }

    public var isFastTravelEnabled: Bool {
        scriptMenus.isFastTravelEnabled
    }

    public func canFastTravel(to marker: ReferenceKey) -> Bool {
        scriptMenus.canFastTravel(to: marker)
    }

    public func addToMap(_ marker: ReferenceKey, allowFastTravel: Bool) {
        scriptMenus.addToMap(marker, allowFastTravel: allowFastTravel)
    }

    public func isMapMarkerVisible(_ marker: ReferenceKey) -> Bool {
        scriptMenus.isMapMarkerVisible(marker)
    }

    public func race(of actor: ReferenceKey) -> FormID? {
        scriptMenus.race(of: actor)
    }

    @discardableResult
    public func setRace(of actor: ReferenceKey, to race: FormID?) -> Bool {
        scriptMenus.setRace(of: actor, to: race)
    }

    public func sex(ofBase base: FormID) -> Int? {
        scriptMenus.sex(ofBase: base)
    }

    public func race(ofBase base: FormID) -> FormID? {
        scriptMenus.race(ofBase: base)
    }

    public func recordFlags(ofBase base: FormID) -> ActorBase.Flags? {
        scriptMenus.recordFlags(ofBase: base)
    }

    public func leveledBase(of actor: ReferenceKey, base: FormID) -> FormID? {
        scriptMenus.leveledBase(of: actor, base: base)
    }

    public func recordShouts(ofBase base: FormID) -> [ReferenceKey] {
        scriptMenus.recordShouts(ofBase: base)
    }

    public func voiceType(ofBase base: FormID) -> FormID? {
        scriptMenus.voiceType(ofBase: base)
    }

    public func giftFilter(ofBase base: FormID) -> FormID? {
        scriptMenus.giftFilter(ofBase: base)
    }

    public func name(of form: FormID) -> String? {
        scriptMenus.name(of: form)
    }

    public func movePlayer(to target: ReferenceKey) {
        scriptMenus.movePlayer(to: target)
    }

    public func openInventory(of actor: ReferenceKey) {
        scriptMenus.openInventory(of: actor)
    }

    public func showTrainingMenu(trainer: ReferenceKey) {
        scriptMenus.showTrainingMenu(trainer: trainer)
    }

    public func showGiftMenu(
        actor: ReferenceKey, giving: Bool, filter: [ReferenceKey?]?, showsStolenItems: Bool
    ) {
        scriptMenus.showGiftMenu(
            actor: actor,
            giving: giving,
            filter: filter,
            showsStolenItems: showsStolenItems
        )
    }

    public func teleportPlayer(_ target: AgentTeleportTarget, openingRaceMenu: Bool) {
        teleports.teleportPlayer(target, openingRaceMenu: openingRaceMenu)
    }

    public func restorePlayerPlace(_ place: SavePlayerPlace) {
        teleports.restorePlayerPlace(place)
    }

    public func followView(_ target: AgentViewTarget) {
        teleports.followView(target)
    }
}
