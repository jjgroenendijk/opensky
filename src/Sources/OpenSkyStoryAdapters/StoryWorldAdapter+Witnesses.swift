import Foundation
import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyCrime
public import OpenSkyDialogue
public import OpenSkyDialogueInterface
public import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyMenusInterface
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyPlayer
public import OpenSkyQuests
public import OpenSkyQuestsInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
public import OpenSkyWorldState
import simd

extension StoryWorldAdapter: SocialEventWorld {}

/// Witnesses that forward to the narrow parts of `StoryWorldAdapter`.
extension StoryWorldAdapter {
    public func commentOnPlayer(_ line: NPCSpeechLine) {
        ambientTalk.commentOnPlayer(line)
    }

    public func sayOwnLine(_ line: NPCSpeechLine, speaker: ReferenceKey) {
        ambientTalk.sayOwnLine(line, speaker: speaker)
    }

    @discardableResult
    public func sayTopic(
        _ subtype: FourCC,
        speaker: ReferenceKey,
        lookAt: ReferenceKey?
    ) -> Float? {
        ambientTalk.sayTopic(subtype, speaker: speaker, lookAt: lookAt)
    }

    public func requestConversation(speaker: ReferenceKey, partner: ReferenceKey) -> Bool {
        storyManager.social.requestConversation(
            speaker: speaker, partner: partner, now: sceneSeconds
        )
    }

    public func questAccess(
        store: WorldStateStore, quests: QuestStore, locations: LocationStore?
    ) -> any QuestAccess {
        var runtime = QuestRuntime(store: store, quests: quests, locations: locations)
        let persistent = locations
            .map { RuntimeReferenceIndex(persistent: $0.persistentPlacements) }
        runtime.referenceSearch = { [weak self] in
            var search = self?.questReferenceSearch()
            search?.persistent = persistent
            search?.isDestroyed = { Self.isDestroyed($0, in: store) }
            if self != nil, let persistent {
                let dead = Self.savedDead(in: store)
                search?.savedDead = dead
                search?.deadBases = Set(dead.compactMap { persistent[$0]?.placedActor?.base })
            }
            return search
        }
        runtime.referenceCreator = { [weak self] base, anchor in
            self?.createQuestReference(base, at: anchor)
        }
        runtime.aliasDataChanged = { [weak self] changes in
            self?.giveAliasData(changes)
        }
        return runtime
    }

    /// Whether a destruction stage or a script marked the object destroyed.
    static func isDestroyed(_ key: ReferenceKey, in store: WorldStateStore) -> Bool {
        store.component(ScriptedReferenceState.self, for: key)?
            .flag(ScriptedStateName.destroyed) == true
    }

    /// Every actor the world state marks dead, in a loaded cell or not.
    static func savedDead(in store: WorldStateStore) -> Set<ReferenceKey> {
        var dead: Set<ReferenceKey> = []
        for key in store.sortedDirtyKeys()
            where store.component(ActorDeathState.self, for: key)?.isDead == true
        {
            dead.insert(key)
        }
        return dead
    }

    public func questReferenceSearch() -> QuestReferenceSearch? {
        socialSearch.questReferenceSearch()
    }

    public func createQuestReference(_ base: FormID, at anchor: ReferenceKey) -> ReferenceKey? {
        socialSearch.createQuestReference(base, at: anchor)
    }

    public func socialFrame(partners: [ReferenceKey]) -> SocialFrame? {
        socialSearch.socialFrame(partners: partners)
    }

    public func socialCanSee(_ observer: SocialActor, _ body: SocialActor) -> Bool {
        socialSearch.socialCanSee(observer, body)
    }

    public func lineDuration(of info: TopicInfo, speaker: ReferenceKey) -> Float? {
        sceneLines.lineDuration(of: info, speaker: speaker)
    }

    public func hasLoadedBody(_ actor: ReferenceKey) -> Bool {
        sceneLines.hasLoadedBody(actor)
    }

    public func conversationPartnersMeet(_ speaker: ReferenceKey, _ partner: ReferenceKey) -> Bool {
        sceneCast.conversationPartnersMeet(speaker, partner)
    }

    public func sceneSpeakerFaces(_ speaker: ReferenceKey, _ listener: ReferenceKey) -> Bool {
        sceneLines.sceneSpeakerFaces(speaker, listener)
    }

    public func voicePaths(of info: FormID, speaker: ReferenceKey) -> [String] {
        sceneLines.voicePaths(of: info, speaker: speaker)
    }

    public func say(_ id: FormID, speaker: ReferenceKey) {
        sceneLines.say(id, speaker: speaker)
    }

    public func speak(
        info id: FormID,
        speaker: ReferenceKey,
        lookAt: ReferenceKey?,
        seconds: Float
    ) {
        sceneLines.speak(info: id, speaker: speaker, lookAt: lookAt, seconds: seconds)
    }

    public var sceneFragments: (any SceneFragmentDispatching)? {
        sceneCast.sceneFragments
    }

    public var sceneSeconds: Double {
        sceneCast.sceneSeconds
    }

    public func runScenePackages(
        _ packages: [FormID], actor: ReferenceKey, owner: ScenePackageOwner
    ) -> ScenePackageState {
        sceneCast.runScenePackages(packages, actor: actor, owner: owner)
    }

    public func releaseScenePackages(actor: ReferenceKey, owner: ScenePackageOwner) {
        sceneCast.releaseScenePackages(actor: actor, owner: owner)
    }

    public func sceneActorStatus(_ actor: ReferenceKey) -> SceneActorStatus {
        var status = sceneCast.sceneActorStatus(actor)
        if sceneLines.isFarFromPlayer(actor) {
            status.insert(.farFromPlayer)
        }
        if sceneLines.isChangingSeat(actor) {
            status.insert(.changingSeat)
        }
        return status
    }

    public func stopQuest(_ quest: FormID) {
        sceneCast.stopQuest(quest)
    }
}
