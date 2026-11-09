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

    public func questAccess(
        store: WorldStateStore, quests: QuestStore, locations: LocationStore?
    ) -> any QuestAccess {
        var runtime = QuestRuntime(store: store, quests: quests, locations: locations)
        runtime.referenceSearch = { [weak self] in self?.questReferenceSearch() }
        runtime.referenceCreator = { [weak self] base, anchor in
            self?.createQuestReference(base, at: anchor)
        }
        return runtime
    }

    public func questReferenceSearch() -> QuestReferenceSearch? {
        socialSearch.questReferenceSearch()
    }

    public func createQuestReference(_ base: FormID, at anchor: ReferenceKey) -> ReferenceKey? {
        socialSearch.createQuestReference(base, at: anchor)
    }

    public func socialFrame() -> SocialFrame? {
        socialSearch.socialFrame()
    }

    public func socialCanSee(_ observer: SocialActor, _ body: SocialActor) -> Bool {
        socialSearch.socialCanSee(observer, body)
    }

    public func lineDuration(of info: TopicInfo, speaker: ReferenceKey) -> Float? {
        sceneLines.lineDuration(of: info, speaker: speaker)
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
        sceneCast.sceneActorStatus(actor)
    }

    public func stopQuest(_ quest: FormID) {
        sceneCast.stopQuest(quest)
    }
}
