// The pure lockpicking model: UESP widths from the install's GMSTs, the turn and
// strain rules, broken picks, perks, and determinism.

@testable import OpenSkyInventory
@testable import OpenSkyInventoryInterface
import Testing

struct LockpickingSessionTests {
    private static let settings = LockpickingSettings.documentedDefaults

    private static func parameters(
        _ difficulty: LockDifficulty,
        skill: Float = 0,
        perks: LockpickingPerkValues = .none
    ) -> LockpickingParameters {
        .make(difficulty: difficulty, skill: skill, settings: settings, perks: perks)
    }

    @Test func widthsFollowTheUESPFormulas() {
        let novice = Self.parameters(.novice)
        #expect(abs(novice.sweetSpotWidth - 30 * 0.82) < 0.001)
        #expect(abs(novice.partialWidth - 22 * 0.775) < 0.001)
        #expect(novice.breakSeconds == 2)
        let master = Self.parameters(.master, skill: 100)
        #expect(abs(master.sweetSpotWidth - 1.875 * 1.42) < 0.001)
        #expect(abs(master.partialWidth - 6 * 2.275) < 0.001)
        #expect(abs(master.breakSeconds - 0.375) < 0.001)
    }

    @Test func skillAboveOneHundredIsClamped() {
        #expect(Self.parameters(.adept, skill: 250) == Self.parameters(.adept, skill: 100))
    }

    @Test func lockLevelsMapToTheirBands() {
        #expect(LockDifficulty(level: 0) == .novice)
        #expect(LockDifficulty(level: 1) == .novice)
        #expect(LockDifficulty(level: 25) == .apprentice)
        #expect(LockDifficulty(level: 26) == .adept)
        #expect(LockDifficulty(level: 100) == .master)
        #expect(LockDifficulty(level: 255) == .requiresKey)
        #expect(!LockDifficulty.requiresKey.isPickable)
    }

    @Test func allowedRotationFallsAcrossThePartialZone() {
        let session = LockpickingSession(
            parameters: LockpickingParameters(
                difficulty: .adept, sweetSpotWidth: 10, partialWidth: 20, breakSeconds: 1
            ),
            sweetSpotCenter: 0,
            picks: 1
        )
        #expect(session.allowedRotation(at: 4) == 1)
        #expect(abs(session.allowedRotation(at: 15) - 0.5) < 0.001)
        #expect(session.allowedRotation(at: -40) == 0)
    }

    @Test func turningInTheSweetSpotOpens() {
        var session = LockpickingSession(
            parameters: Self.parameters(.novice),
            sweetSpotCenter: 0,
            picks: 1
        )
        var events: [LockpickingEvent] = []
        for _ in 0 ..< 10 where events.isEmpty {
            events = session.step(0.1, input: LockpickingInput(pickDelta: 0, turning: true))
        }
        #expect(events == [.opened])
        #expect(session.isFinished)
        #expect(session.picksBroken == 0)
    }

    @Test func strainingBreaksAPickAfterTheBreakTime() {
        var session = LockpickingSession(
            parameters: Self.parameters(.novice),
            sweetSpotCenter: 60,
            picks: 2
        )
        let turn = LockpickingInput(pickDelta: 0, turning: true)
        #expect(session.step(1.9, input: turn).isEmpty)
        #expect(session.isStraining(turn))
        #expect(session.step(0.2, input: turn) == [.pickBroke])
        #expect(session.picksRemaining == 1)
        #expect(session.pickHealth == 1)
        #expect(session.lockRotation == 0)
    }

    @Test func releasingTheTurnStopsTheStrainAndReturnsTheLock() {
        var session = LockpickingSession(
            parameters: Self.parameters(.novice),
            sweetSpotCenter: 20,
            picks: 1
        )
        _ = session.step(0.5, input: LockpickingInput(pickDelta: 0, turning: true))
        let health = session.pickHealth
        _ = session.step(1, input: .idle)
        #expect(session.lockRotation == 0)
        #expect(session.pickHealth == health)
    }

    @Test func unbreakablePicksNeverBreak() {
        let perks = LockpickingPerkValues(unbreakable: true)
        var session = LockpickingSession(
            parameters: Self.parameters(.master, perks: perks), sweetSpotCenter: 80, picks: 1
        )
        for _ in 0 ..< 100 {
            #expect(session.step(0.5, input: LockpickingInput(pickDelta: 0, turning: true)).isEmpty)
        }
        #expect(session.picksRemaining == 1)
    }

    @Test func sweetSpotPerksWidenTheSpot() {
        let plain = Self.parameters(.novice)
        let perked = Self.parameters(.novice, perks: LockpickingPerkValues(sweetSpotFactor: 2))
        #expect(abs(perked.sweetSpotWidth - plain.sweetSpotWidth * 2) < 0.001)
    }

    @Test func locksmithStartsAFreshPickNearTheSweetSpot() {
        let perks = LockpickingPerkValues(startingArc: 45)
        let session = LockpickingSession(
            parameters: Self.parameters(.expert, perks: perks),
            sweetSpotCenter: 40,
            picks: 1,
            startingOffset: -1
        )
        #expect(abs(session.pickAngle - 17.5) < 0.001)
    }

    @Test func thePickStaysInsideItsArc() {
        var session = LockpickingSession(
            parameters: Self.parameters(.novice),
            sweetSpotCenter: 0,
            picks: 1
        )
        _ = session.step(0.1, input: LockpickingInput(pickDelta: 500, turning: false))
        #expect(session.pickAngle == 90)
    }

    @Test func aSessionWithoutPicksIsAlreadyFinished() {
        var session = LockpickingSession(
            parameters: Self.parameters(.novice),
            sweetSpotCenter: 0,
            picks: 0
        )
        #expect(session.isFinished)
        #expect(session.step(1, input: LockpickingInput(pickDelta: 0, turning: true)).isEmpty)
    }

    @Test func theRandomSourceIsDeterministic() {
        var first = LockpickingRandom(seed: 7)
        var second = LockpickingRandom(seed: 7)
        let draws = (0 ..< 5).map { _ in first.uniform(in: -90 ... 90) }
        #expect(draws == (0 ..< 5).map { _ in second.uniform(in: -90 ... 90) })
        #expect(draws.allSatisfy { (-90 ... 90).contains($0) })
    }
}
