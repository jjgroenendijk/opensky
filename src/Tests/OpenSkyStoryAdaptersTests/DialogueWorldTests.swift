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

    @Test func theConditionContextCarriesSpeechCheckFactors() {
        host.fakeRuntimeState.conditionContextResult = ConditionContext()
        host.fakeDialogue.conversationSpeaker = Self.speaker
        host.fakePerks.multiplierResult = 2
        let context = adapter.conditionContext()
        #expect(context.speechChecks.intimidationFactor == 2)
        #expect(context.speechChecks.bribeFactor == 2)
        #expect(context.speechChecks.playerGold == nil)
        #expect(host.fakePerks.multiplierCalls.map(\.target) == [Self.speaker, Self.speaker])
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
        #expect(host.fakeStreamer.stopActorCalls == [Self.speaker])
        #expect(host.fakeStreamer.faceActorCalls.map(\.actor) == [Self.speaker])
        #expect(host.fakeStreamer.releaseActorFacingCalls == [Self.speaker])
    }

    @Test func aWonBribeReportsTheEventStatAndSkill() {
        adapter.run([.speechChallengeWon(.bribe, speaker: Self.speaker)])
        let event = host.fakeStoryWorld.reportStoryEventCalls.first
        #expect(event?.event == "BRIB")
        #expect(event?.actor1 == Self.speaker)
        #expect(host.fakeWorldState.incrementMiscStatCalls.map(\.name) == ["Bribes"])
        #expect(host.fakeProgression.reportSpeechCheckWonCallCount == 1)
    }
}
