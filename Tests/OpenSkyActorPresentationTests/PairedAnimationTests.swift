// A paired idle starts two graphs: the lead's on the idle's event and the partner's on the
// event with `pa_` toggled, the partner standing on the lead. Each half's prefixed events
// lose their prefix, and the pair ends on the clip's end event or a timeout.

@testable import OpenSkyActorPresentation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyNavigation
import OpenSkyRuntimeState
import simd
import Testing

@MainActor
private final class PairedIdleWorld: IdleWorld {
    var takesEvent: Set<ReferenceKey> = []
    var raised: [(event: String, actor: ReferenceKey)] = []
    var aligned: [(partner: ReferenceKey, lead: ReferenceKey)] = []

    func idleReferencePlacements() -> [IdleReferencePlacement]? {
        nil
    }

    func idleActors() -> [IdleActorPresence] {
        []
    }

    func idleConditionContext() -> ConditionContext {
        ConditionContext()
    }

    var idleStateSequence: UInt64 {
        0
    }

    func actorPlayback(for _: ReferenceKey) -> ActorAnimationPlayback? {
        nil
    }

    var idleAnimationTime: Float? {
        0
    }

    func moveActor(_: ReferenceKey, to _: SIMD3<Float>) -> NPCMoveCommandResult {
        .started
    }

    func setProp(_: ActorPropAttachment?, on _: ReferenceKey) {}
    func idleAnimationEvent(_: String, on _: ReferenceKey) {}

    func raiseIdleEvent(_ name: String, state _: String?, on actor: ReferenceKey) -> Bool {
        raised.append((name, actor))
        return takesEvent.contains(actor)
    }

    func alignPairedActor(_ partner: ReferenceKey, with lead: ReferenceKey) {
        aligned.append((partner, lead))
    }
}

@MainActor
struct PairedAnimationTests {
    private static let killer = ReferenceKey.plugin(name: "skyrim.esm", objectID: 1)
    private static let victim = ReferenceKey.plugin(name: "skyrim.esm", objectID: 2)
    private static let player = ReferenceKey.player

    private static func play(_ event: String = "pa_KillMoveC") -> PairedAnimationPlay {
        PairedAnimationPlay(
            lead: killer, partner: victim, idle: "1HMKillMoveC", event: event, start: 0
        )
    }

    @Test func eachGraphTakesItsOwnEvent() {
        let world = PairedIdleWorld()
        world.takesEvent = [Self.killer, Self.victim]
        let idles = IdleCoordinator(world: world, data: nil)
        let report = idles.firePaired(Self.play(), trace: [])
        #expect(report.failure == nil)
        #expect(world.raised.map(\.actor) == [Self.killer, Self.victim])
        #expect(world.raised.map(\.event) == ["pa_KillMoveC", "KillMoveC"])
        #expect(world.aligned.map(\.partner) == [Self.victim])
        #expect(idles.pairedAnimation(of: Self.victim)?.isKillMove == true)
    }

    @Test func aLeadThatRefusesTheEventStartsNoPair() {
        let world = PairedIdleWorld()
        world.takesEvent = [Self.victim]
        let idles = IdleCoordinator(world: world, data: nil)
        let report = idles.firePaired(Self.play(), trace: [])
        #expect(report.seconds == 0)
        #expect(report.failure != nil)
        #expect(world.raised.map(\.actor) == [Self.killer])
        #expect(idles.pairs.isEmpty)
    }

    @Test func eachHalfsEventsLoseTheirPrefixAndTheEndEventEndsThePair() {
        let world = PairedIdleWorld()
        world.takesEvent = [Self.killer, Self.victim]
        let idles = IdleCoordinator(world: world, data: nil)
        idles.firePaired(Self.play(), trace: [])
        #expect(idles.ownGraphEvent("NPCSoundPlay.NPCKillMelee", from: Self.killer)
            == "SoundPlay.NPCKillMelee")
        #expect(idles.ownGraphEvent("2_KillActor", from: Self.victim) == "KillActor")
        #expect(idles.ownGraphEvent("NPCSoundPlay.X", from: Self.player) == "NPCSoundPlay.X")
        #expect(idles.pairs.count == 1)
        #expect(idles.ownGraphEvent("2_PairEnd", from: Self.victim) == "PairEnd")
        #expect(idles.pairs.isEmpty)
        #expect(idles.ownGraphEvent("2_KillActor", from: Self.victim) == "2_KillActor")

        idles.firePaired(Self.play(), trace: [])
        idles.expirePairs(now: PairedAnimationCore.maximumSeconds - 1)
        #expect(idles.pairs.count == 1)
        idles.expirePairs(now: PairedAnimationCore.maximumSeconds)
        #expect(idles.pairs.isEmpty)
    }

    @Test func thePartnerTakesTheEventWithPaToggled() {
        #expect(PairedAnimationCore.partnerEvent(of: "pa_VampireFeedStanding_Front")
            == "VampireFeedStanding_Front")
        #expect(PairedAnimationCore.partnerEvent(of: "HorseEnter") == "pa_HorseEnter")
        #expect(PairedAnimationCore.ownEvent("NPCpairedStop") == "pairedStop")
        #expect(PairedAnimationCore.ownEvent("NPC") == nil)
        #expect(PairedAnimationCore.ownEvent("SoundPlay.NPCKillMelee") == nil)
    }

    @Test func onlyPaEventsArePairedAndOnlyKillMovesAreKillMoves() {
        #expect(PairedAnimationCore.isPaired(event: "pa_VampireFeedStanding_Front"))
        #expect(!PairedAnimationCore.isPaired(event: "IdleCannibalFeedStanding"))
        #expect(!Self.play("pa_VampireFeedStanding_Front").isKillMove)
        #expect(Self.play("PA_KILLMOVE2HMSLASH").isKillMove)
        #expect(PairedAnimationCore.ends(onEvent: "pairedStop"))
        #expect(!PairedAnimationCore.ends(onEvent: "KillMoveEnd"))
    }
}
