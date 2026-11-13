// The crime actors and jail parts move, stop, and read actors, and guard each jail step.

import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyCrime
import OpenSkyFormatsESM
import OpenSkySessionTesting
import OpenSkyStoryAdapters
import OpenSkyWorldInterface
import Testing

@MainActor
struct CrimeActorsJailTests {
    private let host = StoryHost()
    private let adapter: CrimeWorldAdapter
    private static let alive = ReferenceKey.plugin(name: "base.esm", objectID: 0x20)
    private static let dead = ReferenceKey.plugin(name: "base.esm", objectID: 0x21)
    private static let marker = ReferenceKey.plugin(name: "base.esm", objectID: 0x60)

    init() {
        adapter = CrimeWorldAdapter(game: host)
    }

    @Test func onlyLivingActorsAreObservers() {
        host.fakeActorWorld.combatActorsResult = [
            CombatActorObservation(key: Self.alive, feet: .zero),
            CombatActorObservation(key: Self.dead, feet: .zero, isDead: true)
        ]
        #expect(adapter.livingActors().map(\.key) == [Self.alive])
        #expect(adapter.actorsDetectingPlayer().isEmpty)
    }

    @Test func deathComesFromTheWorldState() {
        host.fakeWorldState.componentResult = ActorDeathState(isDead: true)
        #expect(adapter.isDead(Self.dead))
        #expect(host.fakeWorldState.componentCalls == [Self.dead])
    }

    @Test func movesStopsAndPackagesReachTheirPorts() {
        host.fakeStreamer.actors.moveActorResult = .started
        #expect(adapter.moveActor(Self.alive, to: .zero) == "started")
        adapter.stopActor(Self.alive)
        adapter.suspendPackage(for: Self.alive)
        adapter.resumePackage(for: Self.alive)
        #expect(host.fakeStreamer.actors.stopActorCalls == [Self.alive])
        #expect(host.fakePackages.suspendCalls == [Self.alive])
        #expect(host.fakePackages.resumeCalls == [Self.alive])
    }

    @Test func dialogueReadsAndBeginsThroughTheMenu() {
        host.fakeDialogueMenu.isOpen = true
        host.fakeDialogue.lastOutcome = "won"
        #expect(adapter.isDialogueOpen)
        #expect(adapter.lastDialogueOutcome == "won")
        adapter.beginDialogue(with: Self.alive)
        #expect(host.fakeDialogueMenu.beginCalls == [Self.alive])
    }

    @Test func withoutASessionTheJailClockIsMissing() {
        #expect(adapter.gameSeconds == nil)
        #expect(adapter.hourOfDay == nil)
        #expect(adapter.playerFeet == nil)
        adapter.passGameTime(days: 3)
        #expect(!adapter.movePlayer(toMarker: Self.marker))
    }

    @Test func jailDoorsNeedAPlacedMarker() {
        #expect(!adapter.enterJail(through: Self.marker))
        #expect(!adapter.leaveJail(to: Self.marker))
        #expect(host.fakeStreamer.requestDoorTransitionCalls.isEmpty)
        #expect(adapter.wearJailOutfit(FormID(0x70)).isEmpty)
    }

    @Test func jailProgressAndLockpicksComeFromTheirPorts() {
        host.fakeProgression.loseJailProgressResult = [1, 2]
        #expect(adapter.loseJailProgress(days: 4, maximumDays: 10) == 2)
        #expect(host.fakeProgression.loseJailProgressCalls.map(\.days) == [4])
        #expect(adapter.lockpickItem == nil)
    }
}
