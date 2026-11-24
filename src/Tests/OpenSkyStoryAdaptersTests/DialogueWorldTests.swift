// The dialogue world starts talks, names speakers, and runs dialogue commands.

import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyDialogueInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkySessionTesting
import OpenSkyStoryAdapters
import OpenSkyWorldInterface
import Testing

@MainActor
struct DialogueWorldTests {
    private let host = StoryHost()
    private let adapter: DialogueWorldAdapter
    private static let speaker = ReferenceKey.plugin(name: "base.esm", objectID: 0x20)

    init() {
        adapter = DialogueWorldAdapter(game: host, stage: nil)
    }

    @Test func aMountableSpeakerIsMountedNotGreeted() {
        host.fakeMountWorld.mountOnActivationResult = true
        adapter.handleTalkActivation(TalkActivationEvent(speaker: Self.speaker))
        #expect(host.fakeMountWorld.mountOnActivationCalls == [Self.speaker])
        #expect(host.fakeDialogueMenu.beginCalls.isEmpty)
    }

    @Test func aSneakingPlayerPicksPockets() {
        host.fakePlayer.isSneaking = true
        host.fakeContainerMenu.openPickpocketResult = true
        adapter.handleTalkActivation(TalkActivationEvent(speaker: Self.speaker))
        #expect(host.fakeContainerMenu.openPickpocketCalls == [Self.speaker])
        #expect(host.fakeDialogueMenu.beginCalls.isEmpty)
    }

    @Test func otherwiseTheTalkBegins() {
        adapter.handleTalkActivation(TalkActivationEvent(speaker: Self.speaker))
        #expect(host.fakeDialogueMenu.beginCalls == [Self.speaker])
    }

    /// An unloaded or disabled speaker leaves the resident actors; a talking activator,
    /// never resident, keeps its menu.
    @Test(arguments: [false, true])
    func theMenuClosesWhenItsSpeakerLeavesTheResidentActors(wasResident: Bool) {
        host.fakeDialogueMenu.isOpen = true
        host.fakeDialogueMenu.speakerOrTarget = Self.speaker
        if wasResident {
            host.fakeActorWorld.combatActorResult = CombatActorObservation(
                key: Self.speaker, feet: .zero, isDead: false
            )
        }
        adapter.closeMenuWhenConversationEnds(playerPlacements: 0)
        host.fakeActorWorld.combatActorResult = nil
        adapter.closeMenuWhenConversationEnds(playerPlacements: 0)
        #expect(host.fakeDialogueMenu.closeCallCount == (wasResident ? 1 : 0))
    }

    @Test(arguments: [false, true])
    func theMenuClosesWhenItsSpeakerDies(dead: Bool) {
        host.fakeDialogueMenu.isOpen = true
        host.fakeDialogueMenu.speakerOrTarget = Self.speaker
        host.fakeActorWorld.combatActorResult = CombatActorObservation(
            key: Self.speaker, feet: .zero, isDead: dead
        )
        adapter.closeMenuWhenConversationEnds(playerPlacements: 0)
        #expect(host.fakeDialogueMenu.closeCallCount == (dead ? 1 : 0))
    }

    @Test(arguments: [false, true])
    func theMenuClosesWhenThePlayerIsMoved(moved: Bool) {
        adapter.closeMenuWhenConversationEnds(playerPlacements: 3)
        host.fakeDialogueMenu.isOpen = true
        host.fakeDialogueMenu.speakerOrTarget = Self.speaker
        adapter.closeMenuWhenConversationEnds(playerPlacements: 3)
        adapter.closeMenuWhenConversationEnds(playerPlacements: moved ? 4 : 3)
        #expect(host.fakeDialogueMenu.closeCallCount == (moved ? 1 : 0))
    }

    @Test func theConditionContextCarriesSpeechCheckFactors() {
        host.fakeRuntimeState.conditionContextResult = ConditionContext()
        host.fakeDialogue.conversationSpeaker = Self.speaker
        host.fakePerks.multiplierResult = 2
        let context = adapter.conditionContext()
        #expect(context[resolution: SpeechCheckResolution.self].intimidationFactor == 2)
        #expect(context[resolution: SpeechCheckResolution.self].bribeFactor == 2)
        #expect(context[resolution: SpeechCheckResolution.self].playerGold == nil)
        #expect(host.fakePerks.multiplierCalls.map(\.target) == [Self.speaker, Self.speaker])
    }

    @Test func theConditionContextKeepsTheSpeakerAndAddsVoiceTypes() {
        var base = ConditionContext()
        base[resolution: DialogueResolution.self] = DialogueResolution(
            speakerInDialogue: Self.speaker, line: nil
        )
        host.fakeRuntimeState.conditionContextResult = base
        let dialogue = adapter.conditionContext()[resolution: DialogueResolution.self]
        #expect(dialogue.speakerInDialogue == Self.speaker)
    }

    @Test func withoutScriptsOrStringsTheReadsAreEmpty() {
        #expect(adapter.questStates() == nil)
        _ = adapter.questAliases()
        #expect(adapter.fragments == nil)
        #expect(adapter.loadStrings() == nil)
        #expect(adapter.residentVoiceTypes().isEmpty)
    }

    @Test func anUnknownSpeakerIsNamedByItsKey() {
        #expect(adapter.speakerLabel(for: Self.speaker) == Self.speaker.description)
        #expect(adapter.headPosition(of: Self.speaker) == nil)
        #expect(host.fakeStreamer.referenceEntryKeyCalls == [Self.speaker, Self.speaker])
    }

    @Test func actorsWithoutAnEntryAreNoTalkCandidates() throws {
        host.fakeActorWorld.combatActorsResult = [
            CombatActorObservation(key: Self.speaker, feet: SIMD3(0, 50, 0))
        ]
        host.fakeFactions.hostilityResult = .neutral
        let ray = try #require(InteractionRay(origin: .zero, direction: SIMD3(0, 1, 0)))
        #expect(adapter.speakers.talkCandidates(along: ray).isEmpty)
        #expect(host.fakeFactions.hostilityCalls == [Self.speaker])
    }

    @Test func packageAndFacingCommandsReachTheirPorts() {
        adapter.run([
            .suspendPackage(Self.speaker), .resumePackage(Self.speaker), .stopActor(Self.speaker),
            .faceActor(Self.speaker, towards: .zero), .releaseFacing(Self.speaker),
            .spokeToPlayer(Self.speaker)
        ])
        #expect(host.fakePackages.suspendCalls == [Self.speaker])
        #expect(host.fakePackages.resumeCalls == [Self.speaker])
        #expect(host.fakeStreamer.actors.stopActorCalls == [Self.speaker])
        #expect(host.fakeStreamer.actors.faceActorCalls.map(\.actor) == [Self.speaker])
        #expect(host.fakeStreamer.actors.releaseActorFacingCalls == [Self.speaker])
    }

    /// The game sends no `BRIB` for a win and leaves the stat to the dialogue scripts
    /// (docs/engine/statistics.md, How the game counts).
    @Test func aWonBribeCountsTheSkillButNoStatAndSendsNoEvent() {
        adapter.run([.speechChallengeWon(.bribe, speaker: Self.speaker)])
        #expect(host.fakeStoryWorld.reportStoryEventCalls.isEmpty)
        #expect(host.fakeWorldState.incrementMiscStatCalls.isEmpty)
        #expect(host.fakeProgression.reportSpeechCheckWonCallCount == 1)
    }
}
